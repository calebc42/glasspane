# AUDIT — full-SPEC conformance sweep (RAW, VERIFICATION INCOMPLETE)
Run 2026-07-23, workflow `wf_3a38ced5-5ef`, against `ebp/SPEC.md` @ 4f6f82b
(amendments through #62; submodule bumped to match in commit c5165e5).

> **STATUS: NOT A VERIFIED AUDIT.** 25 of 27 section auditors returned
> **230 raw findings**. Adversarial verification (3 diverse lenses per finding,
> 690 verdicts needed) reached only **46 verdicts covering 17 findings** before
> the run was halted for usage. Everything marked `unverified` below is an
> UNTESTED CLAIM — per the known verifier-failure trap, absence of a verdict is
> NOT refutation. Findings are also NOT deduplicated across auditors.

## Coverage holes (auditors that died before returning)
- Audit SS24 (conformance) — SS24.1 profiles, SS24.2 the endpoint duty lists, SS24
- Audit consistency ACROSS the normative artifacts rather than within one. Compare

## Counts

| kind | P1 | P2 | P3 | total |
|---|---|---|---|---|
| IMPL | 34 | 79 | 22 | 135 |
| SPEC | 6 | 43 | 29 | 78 |
| TEST | 0 | 3 | 7 | 10 |
| PLANNED-GAP | 0 | 4 | 3 | 7 |
| **all** | | | | **230** |

## Verified sample (13 findings with all 3 lenses)

11 CONFIRMED, 1 contested, 2 REFUTED (both SPEC/P3). 7 of 39 individual lens
votes refuted. The sample is biased toward the §13/§14 auditors, which
finished first — do not extrapolate the survival rate to the whole set.

---

# IMPL findings (135)

## [P1] [unverified] SS14.4 — A remote ActionDescriptor inside a dialog is silently discarded: no event.action with dialog_id is ever constructed

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:256  
**SPEC line:** 1381  
**Auditor:** Audit SS14.4 through SS14.6 (the event.action request protocol, EventI

**SPEC quote:**
> A surface event MUST contain `surface` and `revision_seen` and MUST omit `dialog_id`. A dialog event MUST contain `dialog_id` and MUST omit `surface` and `revision_seen`.

**Detail:** SS18.1 (SPEC.md:2235-2238) makes the path REQUIRED: 'A remote action inside a dialog uses `event.action.dialog_id` and MAY use its own `capture_fields`. Every such remote ActionDescriptor MUST set or default `when_offline` to `drop`; `queue` and `wake` are invalid because a dialog has no durable instance identity.' Grepping the whole implementation, `dialog_id` appears only as a dialog.show param key (CompanionEngine.kt:1398) and in the presentation listener — there is no code anywhere that puts "dialog_id" into event.action params. The renderer routes a dialog button's non-builtin on_tap through the ordinary surface path: onButton (Renderer.kt:525-546) falls through to ctx.action(onTap) -> DeviceBridge.action(ctx.surface, ...) with ctx.surface == "dialog:<id>" (Renderer.kt:115), and dispatchAction's first act is `val revision = surfaces.revisionOf(surface) ?: return` (CompanionEngine.kt:256). A dialog is never in SurfaceStore (its ID does not even match the SURFACE_ID regex in SurfaceStore.kt:11), so revisionOf returns null and the call returns with no event, no error, and no diagnostic. Relatedly, dialog specs are validated with the plain validateSurfaceSpec (CompanionEngine.kt:1415), so the SS18.1 'queue and wake are invalid' rule for dialog descriptors is unenforced too.

**Failure scenario:** Emacs sends dialog.show {dialog_id:"rename", spec:{t:"column", children:[{t:"text_input", id:"name"}, {t:"button", label:"Save as copy", on_tap:{action:"file.save-copy", capture_fields:["name"]}}]}}. The user types a name and taps 'Save as copy'. The Companion produces nothing at all: no event.action, no error response, no local diagnostic; the dialog stays outstanding forever and Emacs's registered file.save-copy handler is never reached. Any dialog whose UI mixes a remote action with the submit/dismiss builtins is silently non-functional.

**Proposed fix:** Give dispatchAction a dialog form: when the surface key is "dialog:<id>" and that dialog is outstanding, build params with dialog_id and WITHOUT surface/revision_seen, resolve capture_fields from the dialog-local field map (DialogContext.fields) rather than SurfaceStore, force when_offline to drop (and reject queue/wake at dialog.show validation with 1201), and send it as a live request. Add a validator flag (inDialog) to validateSurfaceSpec so a queue/wake remote descriptor inside a dialog spec rejects the dialog.show atomically.

## [P1] [unverified] SS14.6 — A password-bearing on_submit with when_offline queue/wake is durably persisted: the secret is written to the queue file and replayed later

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:306  
**SPEC line:** 1518  
**Auditor:** Audit SS14.4 through SS14.6 (the event.action request protocol, EventI

**SPEC quote:**
> A remote descriptor that captures a password MUST use `when_offline: "drop"`, MUST NOT use `dedupe` or `ttl_s`, and MUST NOT create an event unless an authenticated `READY` session exists. ... The Companion MUST hold the value only in volatile memory, place it only in the explicitly submitted action's or dialog result's `fields`, transmit it without durable admission, and erase its local copy as soon as the request concludes or the interaction is cancelled. A password value MUST NOT appear in `args`, a builtin parameter value, a retry queue, diagnostics, or crash recovery.

**Detail:** Nothing on the Companion cross-checks a password node against the offline policy. SpecValidator.validateAction (SpecValidator.kt:879-955) validates when_offline/ttl_s/dedupe consistency and resolves capture_fields against ctx.statefuls, but never inspects whether a captured/submitting node has `password: true`; the only password rules in the validator are the reset_input_ids ban (SpecValidator.kt:142) and the seed/on_change ban (SpecValidator.kt:415-418), neither of which touches the policy. At dispatch, RenderTextInput's submit() routes a password through ctx.actionWithFields (Renderer.kt:256) -> DeviceBridge.actionWithFields (DeviceBridge.kt:173) -> CompanionEngine.dispatchAction, where extraFields are merged into `fields` unconditionally (CompanionEngine.kt:284) and the policy branch at CompanionEngine.kt:302-308 calls queue.admit(params, ...) for `queue`/`wake`. DurableQueue.admit stores the whole params object (DurableQueue.kt:108-140) and FileQueueStore.replace writes it as cleartext JSON to ebp-queue.json with an fsync (QueueStore.kt:52-60). The same branch also admits while the session is not READY, contradicting 'MUST NOT create an event unless an authenticated READY session exists'. Note the leak does not even require capture_fields: the renderer synthesizes fields.<id> for any password on_submit.

**Failure scenario:** Emacs pushes app:login = {t:text_input, id:"pw", password:true, on_submit:{action:"auth.login", when_offline:"queue", ttl_s:3600}}. The document validates (no seeded value, no on_change, queue has its ttl_s). The user types "hunter2" and presses Done while the phone is offline. dispatchAction builds params with fields:{"pw":"hunter2"} and calls queue.admit, which fsyncs {"records":[{"event":{..."fields":{"pw":"hunter2"}...}}]} to the app-private ebp-queue.json. The plaintext password now survives process death, is re-read by DurableQueue.init on the next start, and is replayed to Emacs up to an hour later — a durable admission of a secret that SS14.6 forbids outright.

**Proposed fix:** In SpecValidator: record the offline policy alongside each capture ref and, in the deferred capture-resolution loop (SpecValidator.kt:118-125), throw ContentInvalid when a resolved node has password:true and the descriptor's when_offline is not "drop" or it carries dedupe/ttl_s. Also reject a password text_input whose on_submit is not drop-policy (the renderer-synthesized field case), and apply the same rule to a dialog.submit builtin's capture_fields. Defensively, in CompanionEngine.dispatchAction, before the policy branch, force-fail (local diagnostic, no admission) when extraFields is non-empty or any capture name resolves to surfaces.isPasswordNode() and policy != "drop".

## [P1] [unverified] §10.2 — Welcome `granted` and `surface_profiles` are absorbed but never enforced — every capability-gated sender emits unconditionally

**Location:** `emacs/ebp.el`:662  
**SPEC line:** None  
**Auditor:** Audit emacs/ebp.el as a whole against every SPEC duty assigned to "a c

**SPEC quote:**
> Emacs MUST NOT invoke a
capability-gated method or emit capability-gated content unless the capability
was granted.

**Detail:** `ebp-client--on-welcome` stores the welcome's `granted` and `surface_profiles` into the client struct (ebp.el:662-663), but `ebp-client-granted` and `ebp-client-profiles` are read nowhere in the file — `grep -n "granted\|surface_profiles\|node_types" emacs/` returns only the struct slot, the required-member list, and the two setf sites. There is no gating helper anywhere under `emacs/`. Consequently every capability-gated sender writes to the wire regardless of the grant: `ebp-client-surface-update`/`-remove` (ebp.el:1115-1137, gated per §11 on the surface capability for the namespace), `ebp-client-toast` (1141, `presentation.toast`), `ebp-client-theme-set` (1151, `theme`), `ebp-client-reminders-set` (1166, `reminders.owner`), `ebp-client-capability-invoke` (1187, `capabilities`), `ebp-client-triggers-set` (1208, `triggers`), `ebp-client-pie-menu-show`/`-dismiss` (1227/1239, `presentation.pie-menu`), `ebp-client-dialog-show` (1245, `surfaces.dialog`). §13.1 (SPEC line 1004) additionally requires the namespace gate: "`surface.update` MUST reject a namespace whose required capability/profile was not granted". Node/builtin/feature gating against the target profile (§10.2 line 849) is likewise absent — nothing walks a `spec` against `surface_profiles.<target>.node_types`/`builtins`/`features`. §24.2 line 3450 lists "explicit capability and per-target node, builtin, and feature gating" as an Emacs core conformance MUST, so this is endpoint duty, not the deferred application layer.

**Failure scenario:** Emacs sends `wants: ["theme","surfaces.widget","surfaces.dialog"]`; the Companion supports none and returns `granted: []` with `surface_profiles` containing only `app`. The application then calls `(ebp-client-theme-set c :dark t)` -> a `theme.set` notification is written; `(ebp-client-dialog-show c "rename" spec)` -> a `dialog.show` request is written; `(ebp-client-surface-update c "widget:agenda" spec)` -> a `surface.update` for the `widget:` namespace is written AND `ebp-client--surface-request` (ebp.el:1101-1103) burns revision 0 into the local floor table before the Companion answers 1001/-32601/1201. Three Emacs MUST NOTs violated on a single conformant Companion that simply granted nothing. The same absence lets a `spec` containing e.g. `{"t":"chart"}` be pushed to `app:*` when the `app` profile's `node_types` omits `chart`.

**Proposed fix:** Add `ebp-client-granted-p (client cap)` reading the absorbed `granted` list and `ebp-client--profile-for (client surface)` returning the `surface_profiles` entry for the `app`/`notification`/`widget`/`tile`/`dialog` target. Guard each sender: signal a local error (never a wire frame) when the required capability is absent. In `ebp-client--surface-request`, resolve the namespace's required capability and refuse before claiming a revision, exempting `surface.remove` for any surface present in the welcome's `surfaces` map (§13.1 line 1005-1006). Add a `ebp-client--gate-spec` walk that rejects any node `t`, builtin `action`, or constraining feature not listed in the resolved profile, treating a missing profile or missing list as support for nothing.

## [P1] [unverified] §10.2 — Companion never enforces max_field_bytes / max_input_state_bytes on retained input drafts, so the welcome's input_state can exceed both limits

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SurfaceStore.kt`:249  
**SPEC line:** 826  
**Auditor:** Audit SS10 (session lifecycle and negotiation) — states, the welcome m

**SPEC quote:**
> Every `input_state` value MUST have the JSON type required by its node type and MUST fit `max_field_bytes`, and the complete object MUST fit `max_input_state_bytes` under Section 4.5's limit encoding. Before accepting a non-password user change that would enlarge retained input state beyond that aggregate limit, the Companion MUST refuse the change, preserve the preceding logical and native value, and show a local validation diagnostic. A size-reducing change remains legal. It MUST NOT silently discard another field's newer draft to make room.

**Detail:** Call chain: renderer edit -> DeviceBridge.state() (DeviceBridge.kt:183) -> CompanionEngine.publishState() (CompanionEngine.kt:348) -> SurfaceStore.putDraft() (SurfaceStore.kt:249). putDraft checks only that the id is a stateful node in the accepted snapshot and that it is not `password`; it then stores the value and calls persist(). SurfaceStore's constructor (SurfaceStore.kt:15-30) takes maxSurfaces, maxSurfaceIds, maxCaptureFields, maxChartPoints, maxCanvasOps and the two node-type sets — `max_field_bytes` and `max_input_state_bytes` are never passed in and there is no size check anywhere on the draft path. A grep over all main sources shows the only consumers of those two limits are CompanionEngine.checkLimits() (the §4.5 startup reservation, lines 1594-1600 and 1647), ContextlessEvents.kt:128 (notification inline-reply text) and AppCapabilities.readClipboard (§20.3) — never the input-draft path. SurfaceStore.inputState() (line 236) then serializes every retained draft verbatim into the welcome at CompanionEngine.kt:1554. So neither the per-value MUST, the aggregate MUST, nor the refuse-and-preserve MUST is implemented; there is also no test (no wire test constructs an oversize draft).

**Failure scenario:** Shipped limits (DeviceBridge.kt:71) are max_field_bytes=65536, max_input_state_bytes=262144. `app:notes` carries a multiline `text_input` with id `body`. The user pastes 200,000 ASCII characters into it. publishState -> putDraft stores the 200 KB string and FileSurfaceBacking persists it to ebp-surfaces.json. On the next connection buildWelcome emits `input_state: {"app:notes": {"body": "<200000 bytes>"}}` — one value at 3x max_field_bytes, and 76% of the aggregate budget consumed by a single field; a second such field breaks the aggregate MUST outright. Emacs, which was told 65536 is the maximum encoded bytes per input value, receives a value it is entitled to reject. Because the draft survives process death, every subsequent welcome repeats it; once retained drafts plus the reported `surfaces` object push the welcome body past max_frame_bytes, encodeFrame throws FrameClose (FrameCodec.kt:192-193), the dispatch wrapper converts it to close("dispatch failure: ...") (CompanionEngine.kt:101-105), and the connection dies before any welcome is written — the pairing can never authenticate again, and nothing in the code can shrink the draft.

**Proposed fix:** Thread max_field_bytes and max_input_state_bytes into SurfaceStore. In putDraft, compute the RFC8785/JCS encoded size of the candidate value and of the prospective complete input_state object; if either bound would be exceeded and the change is not size-reducing, refuse the change, leave the previous draft (and the native widget value) untouched, and return a refusal that CompanionEngine surfaces as a local validation diagnostic (never evicting another field's draft to make room). Add wire tests for (a) single-value over max_field_bytes refused, (b) aggregate over max_input_state_bytes refused with the other field's draft intact, (c) a size-reducing change still accepted at the limit.

## [P1] [CONFIRMED] §10.2 — Draft admission enforces neither max_field_bytes nor max_input_state_bytes, so one oversized paste durably bricks the pairing's welcome

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SurfaceStore.kt`:249  
**SPEC line:** 826  
**Auditor:** Audit SS13.5 and SS13.6 (input state, drafts, draft reconciliation on 

**SPEC quote:**
> Every `input_state` value MUST have the JSON type required by its node type and MUST fit `max_field_bytes`, and the complete object MUST fit `max_input_state_bytes` under Section 4.5's limit encoding. Before accepting a non-password user change that would enlarge retained input state beyond that aggregate limit, the Companion MUST refuse the change, preserve the preceding logical and native value, and show a local validation diagnostic.

**Detail:** `SurfaceStore.putDraft` (SurfaceStore.kt:249-256) stores whatever value it is handed after only two checks — the ID must be a stateful node in the accepted snapshot, and the node must not be a password — then persists immediately. There is no per-value size check against `max_field_bytes` and no aggregate check of the resulting `inputState()` object against `max_input_state_bytes`; SurfaceStore does not even receive those limits (its constructor takes maxSurfaces, maxSurfaceIds, maxCaptureFields, maxChartPoints, maxCanvasOps, node-type sets, backing). The sole caller, `CompanionEngine.publishState` (CompanionEngine.kt:348-354), adds no check either, and the renderer's `onValueChange` (Renderer.kt:266-279) commits every keystroke/paste unconditionally. Grep confirms `max_input_state_bytes` is read in exactly one place — the §4.5 welcome reservation arithmetic in checkLimits (CompanionEngine.kt:1595,1647) — and `max_field_bytes` is enforced only for capability results (AppCapabilities.kt:84) and notification inline replies (ContextlessEvents.kt:125). The refuse-the-change / preserve-previous-value / local-diagnostic MUST is entirely absent. Because drafts are written through FileSurfaceBacking (CompanionStores.kt:83) the over-limit state is durable, and `buildWelcome` emits `surfaces.inputState()` verbatim (CompanionEngine.kt:1554-1555) into a frame encoded by `encodeFrame`, which throws FrameClose when the body exceeds max_frame_bytes (FrameCodec.kt:186-189).

**Failure scenario:** Advertised limits are max_field_bytes=65536, max_input_state_bytes=262144, max_frame_bytes=4194304 (DeviceBridge.kt:68-72). Emacs pushes an app:main surface with a text_input id="note". The user pastes a 5 MB text payload from another app into it. onValueChange → bridge.state → publishState → putDraft stores the 5 MB string and fsyncs it into ebp-surfaces.json; the immediate state.changed emit throws FrameClose on the dispatch thread (silently killing that task). From then on every reconnect fails: handleAuth → buildWelcome puts input_state {"app:main":{"note":"<5MB>"}} → emit → encodeFrame throws FrameClose before any welcome is written, so the session can never authenticate. The state is durable, so restarting the app does not help — the pairing is dead until app data is cleared. A milder, guaranteed variant needs no giant paste: eight text_inputs each filled with a legal 64 KiB value yields a 512 KiB input_state, twice the advertised max_input_state_bytes MUST, with no diagnostic and no refusal.

**Proposed fix:** Pass the limits into SurfaceStore and make putDraft a rejecting operation: compute the candidate value's JCS-encoded UTF-8 length and reject when it exceeds max_field_bytes; compute the resulting complete input_state size and reject when it exceeds max_input_state_bytes, leaving the previous draft in place (never evicting another field's draft to make room, and always allowing a size-reducing change). Return the rejection to CompanionEngine.publishState so it suppresses the state.changed and to DeviceBridge/renderer so it restores the preceding native value and shows the local validation diagnostic the SPEC requires.

**Verdicts:**
- `SPEC TEXT` refuted=False (high): SPEC.md:826-833 contains the quoted sentence verbatim in §10.2's normative prose (after the welcome-member schema table, not in the JSON example or a note): "Every `input_state` value MUST have the JSON type required by its node type and MUST fit `max_field_bytes`, and the complete object MUST fit `max_input_state_bytes` under Section 4.5's limit encoding. Before accepting a non-password user chan
- `CODE TRUTH` refuted=False (high): SPEC.md:826-830 makes both bounds a MUST at draft admission ("Every input_state value ... MUST fit max_field_bytes, and the complete object MUST fit max_input_state_bytes ... the Companion MUST refuse the change, preserve the preceding logical and native value, and show a local validation diagnostic"). SurfaceStore.kt:249-256 `putDraft` performs only `records[surface]?.statefuls?.get(id) ?: return

## [P1] [unverified] §13.3 / §13.2 / §13.5 — SurfaceStore reload silently DROPS every present notification:* surface — snapshot, present flag and revision floor are all lost across process death

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SurfaceStore.kt`:54  
**SPEC line:** 1086  
**Auditor:** Audit SS13.1 through SS13.4 (surface namespaces, surface.update / surf

**SPEC quote:**
> The Companion MUST retain enough tombstone information to prevent a delayed older update from recreating the surface. The authenticated welcome MUST report both present snapshots and tombstones. (SPEC.md:1085-1087)  ...  The Companion MUST persist the latest accepted snapshot for each present surface and SHOULD render it while Emacs is disconnected. (SPEC.md:1130-1131)

**Detail:** SurfaceStore's init block re-validates every PRESENT persisted record with `SpecValidator.validateSurfaceSpec(r.spec, ..., advertisedTypes = appNodeTypes)` (SurfaceStore.kt:48-54) and, when validation throws, executes `?: continue` — which skips `records[r.surface] = Record(...)` on line 56 and therefore discards the entire history entry (revision, present, spec, current_view), not just the derived statefuls.  But a `notification:*` record was accepted through the OTHER validator: SurfaceStore.update:132-148 routes the notification namespace to `SpecValidator.validateNotificationSpec`, which requires the root object to be `{body: Node, meta?}` (SpecValidator.kt:169-190). The persisted spec therefore has no `t` member and no `views` member, so `validateSurfaceSpec` hits `if (spec.opt("t") !is String) throw ContentInvalid(path, "surface root must be a node or a multi-view object")` (SpecValidator.kt:114-115) for EVERY notification record.  Call chain: DeviceBridge.kt:44 -> CompanionStores.surfaces() (CompanionStores.kt:71-85, FileSurfaceBacking over ebp-surfaces.json, appNodeTypes = NodeSupport.APP_NODE_TYPES) -> SurfaceStore.init -> drop.  `surfaces.notification` IS in this build's supportedCapabilities (DeviceBridge.kt:60-62), so the path is live, and the durable backing (commit a1b8892) predates notification-surface support (commit a65cd76) — the revalidation was written when only `app:*` specs could be stored. The persistence test only exercises `app:main`/`app:gone` (SurfaceStoreTest.kt:394-411), so nothing catches it. Widget records would break identically if `surfaces.widget` were ever granted, since SurfaceStore.update:150 validates them with validateSurfaceSpec instead of the §13.4 widget wrapper.

**Failure scenario:** Emacs (granted surfaces.notification) sends surface.update {surface:"notification:agenda", revision:12, spec:{body:{t:"text",text:"2 items due"}}}; the Companion answers {status:"applied",revision:12,present:true} and fsyncs it into ebp-surfaces.json. Android kills the app process; the user reopens it. SurfaceStore.init loads the record, validateSurfaceSpec throws on the `{body:...}` root, and the record is dropped. Consequences: (a) the next welcome's `surfaces` object omits notification:agenda entirely, violating §13.3's MUST-report; (b) the stored revision floor is gone, so a delayed/replayed surface.update at revision 5 — which §13.2 requires to return {status:"stale",revision:12,present:true} — instead returns {status:"applied",revision:5,present:true} and overwrites the surface with older content; (c) store.spec("notification:agenda") is null, so the cached snapshot §13.5 requires to be persisted is unavailable and DeviceBridge's surfaceListener (DeviceBridge.kt:256-260) can never re-post or cancel it; (d) the surface silently stops counting against max_surface_ids.

**Proposed fix:** In SurfaceStore.init, dispatch the revalidation on the record's namespace exactly as update() does (validateNotificationSpec for `notification:`, the widget wrapper for `widget:`, validateSurfaceSpec with appNodeTypes for `app:`), and NEVER drop the history on failure: on a revalidation error keep the Record with its revision/present/spec and an empty statefuls map (or keep revision+present and null the spec), so the revision floor and the welcome entry survive even for a spec this build can no longer parse.

## [P1] [CONFIRMED] §13.5 — Present notification:* surfaces are silently dropped at SurfaceStore startup, destroying the persisted snapshot and its revision floor

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SurfaceStore.kt`:48  
**SPEC line:** 1131  
**Auditor:** Audit SS13.5 and SS13.6 (input state, drafts, draft reconciliation on 

**SPEC quote:**
> The Companion MUST persist the latest accepted snapshot for each present surface and SHOULD render it while Emacs is disconnected.

**Detail:** `SurfaceStore.update` dispatches on namespace (SurfaceStore.kt:132): a `notification:*` spec is validated by `validateNotificationSpec` because its shape is the §13.4 wrapper `{body: Node, meta?}`. The startup reload does NOT dispatch on namespace — SurfaceStore.kt:48-54 runs `SpecValidator.validateSurfaceSpec(r.spec, ...)` on EVERY present record and does `.getOrNull() ?: continue`. `validateSurfaceSpec` requires the root to be a multi-view object or a node: `if (spec.opt("t") !is String) throw ContentInvalid(path, "surface root must be a node or a multi-view object")` (SpecValidator.kt:114-115). A persisted `{"body":{...},"meta":{...}}` has neither `views` nor `t`, so it always throws and the whole record is skipped. `surfaces.notification` IS in the reference host's granted set (DeviceBridge.kt:60-62) and FileSurfaceBacking is wired (CompanionStores.kt:83), so this is reachable in the shipped app. The loss is permanent: the very next `persist()` (SurfaceStore.kt:68-76) rewrites ebp-surfaces.json from `records`, which no longer contains the notification history. Orphaned drafts for that surface are still loaded at SurfaceStore.kt:58 and now belong to no record. The only durability test, `durableStoreSurvivesProcessDeath` (SurfaceStoreTest.kt:389-411), uses only `app:*` specs; NotificationSurfaceTest builds in-memory stores only, so nothing covers this branch.

**Failure scenario:** Emacs pushes surface.update {surface:"notification:alarm", revision:7, spec:{body:{t:"text",text:"Meeting at 3"}, meta:{channel:"agenda"}}} → applied, persisted with present=true. The Companion process is killed (Android low-memory / force-stop). On restart CompanionStores.surfaces() reloads: validateSurfaceSpec throws on the {body,meta} root, `continue` drops the record, and the first subsequent mutation persists a file with no notification:alarm entry. Consequences: (1) the cached snapshot the SPEC requires to be persisted is gone; (2) the next authenticated welcome's `surfaces` object omits notification:alarm entirely, violating §13.3's "The authenticated welcome MUST report both present snapshots and tombstones"; (3) the revision floor is reset to -1, so a delayed or replayed surface.update at revision 3 now returns {status:"applied", revision:3} instead of the required {status:"stale", revision:7} and re-posts a superseded notification.

**Proposed fix:** Dispatch on `namespace(r.surface)` in the init loop exactly as `update()` does — `validateNotificationSpec` for `notification:*`, `validateSurfaceSpec` otherwise — and never drop a record on a re-validation failure: keep the surface, its revision, and its present flag (degrading spec to null so it renders nothing) so the floor and the welcome report survive. Extend `durableStoreSurvivesProcessDeath` with a present notification:* record.

**Verdicts:**
- `MATERIALITY` refuted=False (high): SurfaceStore.kt:48-54 unconditionally runs SpecValidator.validateSurfaceSpec on every present record, while update() dispatches on namespace (SurfaceStore.kt:132). SpecValidator.kt:114-115 (`if (spec.opt("t") !is String) throw ContentInvalid(path, "surface root must be a node or a multi-view object")`) throws deterministically on the persisted §13.4 notification wrapper {body,meta}, which has neit
- `SPEC TEXT` refuted=False (high): SPEC.md:1130-1131 is verbatim and normative: "The Companion MUST persist the latest accepted snapshot for each present surface and SHOULD render it while Emacs is disconnected" — the MUST binds persistence (the SHOULD weakens only rendering), it is body prose in §13.5, aimed at the Companion (the endpoint SurfaceStore implements), and §13.5:1136 explicitly requires state to "survive Companion proc
- `CODE TRUTH` refuted=False (high): Reproduced by execution against the built wire.jar: SurfaceStore("notification:alarm", rev 7, spec {body,meta}) persists correctly, but a fresh SurfaceStore over the same FileSurfaceBacking reports snapshot()=={} and spec()==null, and a replayed revision-3 update returns "applied" instead of "stale"@7, then rewrites the file at revision 3. Root cause is exactly as stated: SurfaceStore.kt:48-56 run

## [P1] [CONFIRMED] §13.6 — Renderer keeps showing an erased draft: local input state is never re-seeded when SurfaceStore clears a draft (reset_input_ids / incompatible schema / node-type change)

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt`:236  
**SPEC line:** 1162  
**Auditor:** Audit SS13.5 and SS13.6 (input state, drafts, draft reconciliation on 

**SPEC quote:**
> The Companion MUST clear a dirty value when any of these occurs:

- a later snapshot carries the same value, acknowledging it;
- the node ID disappears from the accepted snapshot;
- the same ID is reused for a different node type or incompatible value schema;
- the ID appears in `reset_input_ids`.

[...] Anything else is incompatible. The Companion MUST erase an incompatible draft and seed the node from the newly authored value or that node's default, without emitting `state.changed` or a user action.

**Detail:** There are two independent copies of every input value: the authoritative wire draft in SurfaceStore (`drafts[(surface,id)]`, cleared by `reconcileDrafts` at SurfaceStore.kt:262-280) and the renderer's Compose-local copy. The renderer's copy is keyed ONLY on `(ctx.surface, id)` and seeded ONCE from the authored value: `rememberSaveable(ctx.surface, id, key = "ti:${ctx.surface}:$id")` (Renderer.kt:236, text_input), `key = "ed:..."` (Renderer.kt:318, editor), `rememberSaveable(ctx.surface, id, key = "in:...")` (InputNodes.kt:185 checkbox, :205 switch), `remember(ctx.surface, id)` (InputNodes.kt:251-253 enum_list, :363 discrete slider, :379 continuous slider). That keying was the W9 audit I9 fix (drafts must not key on the key-first `ctx.path`), and it is correct for draft SURVIVAL — but it makes the renderer copy immortal for the whole surface lifetime. Nothing in the render layer ever reads `SurfaceStore.draft`/`hasDraft`/`currentValue` (grep: those symbols appear only in CompanionEngine.kt and SurfaceStore.kt), and `engine.surfaceListener` (DeviceBridge.kt:252-263) only hands `MainActivity` the new spec JSONObject; `MainActivity` renders it via `RenderNode(s, "app:main", bridge)` with a constant surface string. So when reconcileDrafts erases a draft (SurfaceStore.kt:269-276: id-disappeared, id in reset, node-type change, `!compatible`, or acknowledged), the Compose state's inputs are unchanged and the stale draft keeps being displayed and keeps being the value the user edits from. The three erase-and-reseed branches (reset_input_ids, node-type change, schema-incompatible) therefore produce a persistent UI-vs-wire divergence; only the 'acknowledged' branch is benign because the two values are already equal.

**Failure scenario:** Emacs pushes app:main rev 1 with {t:"text_input", id:"title", value:"Original"} plus a button {on_tap:{action:"doc.save", capture_fields:["title"]}}. The user types "Draft" — Compose state = "Draft", SurfaceStore draft = "Draft", state.changed sent. Emacs rejects the draft per application policy and pushes rev 2 with value:"Server Wins" and reset_input_ids:["title"]. SurfaceStore.reconcileDrafts removes (app:main,title) (SurfaceStore.kt:270) so currentValue() → "Server Wins", and the result is "applied". The renderer's rememberSaveable inputs ("app:main","title") did not change, so the OutlinedTextField still shows "Draft". The user now taps Save: dispatchAction reads surfaces.currentValue (CompanionEngine.kt:278) and sends fields:{title:"Server Wins"} — the opposite of what is on screen. Same divergence for a checkbox retyped as a switch, and for a single_line:false text_input with draft "a\nb" re-pushed as single_line:true (compatible() returns false, wire draft erased, field still shows the U+000A text).

**Proposed fix:** Make the wire store the single source of truth for input values at render time. Either (a) have SurfaceStore bump a per-(surface,id) draft epoch inside reconcileDrafts whenever it removes a draft, expose it, and include it in the remember/rememberSaveable inputs so an erase re-seeds from the authored value; or (b) seed each input node from `store.currentValue(surface, id)` (draft-if-present, else authored value) and hold only transient composition state in Compose. Option (a) is the smaller change and preserves the §16.1 rule that changing only a `key` must not erase a compatible draft.

**Verdicts:**
- `SPEC TEXT` refuted=False (high): The quoted text is verbatim and normative at SPEC.md:1162-1167 ("The Companion MUST clear a dirty value when any of these occurs: ... - the same ID is reused for a different node type or incompatible value schema; - the ID appears in `reset_input_ids`.") and SPEC.md:1183-1185 ("Anything else is incompatible. The Companion MUST erase an incompatible draft and seed the node from the newly authored v
- `CODE TRUTH` refuted=False (high): Reproduced by reading. Renderer.kt:236 seeds the Compose copy once via rememberSaveable(ctx.surface, id, key="ti:${ctx.surface}:$id"){mutableStateOf(node.optString("value"))} — both inputs are constant (MainActivity.kt:80 passes the literal "app:main"; DeviceBridge.kt:261 only re-emits the spec), and RenderTextInput has no LaunchedEffect or other re-seed on node value. SurfaceStore.reconcileDrafts
- `MATERIALITY` refuted=False (high): SPEC.md:1162 ("The Companion MUST erase an incompatible draft and seed the node from the newly authored value or that node's default") and §16.1 (SPEC.md:1677-1680, "changing or removing the input ID, type, or value schema MUST erase it as Section 13.6 requires") make the erase observable at the node, i.e. in presentation — the store has no other notion of a node value. The impl erases only the wi

## [P1] [CONFIRMED] §14.1 — `confirm` is validated but never presented — a confirmed action fires immediately with no confirmation and no decline path

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:251  
**SPEC line:** 1260  
**Auditor:** Audit SS14.1 through SS14.3 (ActionDescriptor shape, the dotted action

**SPEC quote:**
> When `confirm` is present, the Companion MUST present the exact confirmation
before creating, persisting, or delivering the event. Declining MUST be a
clean no-op. The Companion MUST NOT defer this confirmation until replay and
MUST NOT infer confirmation text from a newer surface.

**Detail:** SpecValidator.validateAction (SpecValidator.kt:908-912) type-checks `confirm` as a non-empty string and ACTION_SCHEMA lists it as a legal remote-descriptor member (Vocabulary.kt:69), but nothing in the implementation ever presents it. `grep -rn confirm companion/ --include=*.kt` outside tests yields only the validator, the vocabulary row, and unrelated Compose `confirmButton`/`confirmValueChange` parameters in EditorToolbar.kt/InputNodes.kt/LayoutNodes.kt. Call chain: Renderer.onButton (Renderer.kt:525-548) → RenderCtx.action (Renderer.kt:78) → DeviceBridge.action (DeviceBridge.kt:150) → CompanionEngine.dispatchAction (CompanionEngine.kt:251). dispatchAction reads `args`, `capture_fields`, `when_offline`, `dedupe`, `ttl_s` and builds/persists/sends the event (lines 257-336) without ever reading `confirm`. There is no confirmation composable in render/, no confirm listener on DeviceBridge, and no confirm hook on CompanionEngine. The whole MUST is unimplemented; the descriptor member is accepted and then discarded.

**Failure scenario:** Emacs pushes `app:agenda` containing `{t:"button", label:"Archive all", on_tap:{action:"agenda.archive-all", when_offline:"queue", ttl_s:3600, confirm:"Archive every item? This cannot be undone."}}`. The user taps once. dispatchAction immediately mints an EventId, builds the params, and calls queue.admit (CompanionEngine.kt:306), durably committing the destructive event — no confirmation dialog is ever shown and the user has no decline path. The event then replays to Emacs on the next READY session.

**Proposed fix:** Add a confirmation gate ahead of event creation. Cleanest split: keep `dispatchAction` pure and gate in the presentation layer — give RenderCtx.action/actionInjecting/actionWithFields a pre-dispatch check that, when `descriptor.optString("confirm").isNotEmpty()`, stashes the pending (descriptor, value, injected, extraFields) tuple in an activity-scoped state holder and shows a modal AlertDialog whose body text is the exact `confirm` string; the positive button calls the existing bridge.* dispatch, the negative button and scrim dismissal drop the tuple with no side effect. Because dialog builtins and notification-action taps bypass RenderCtx, also gate CompanionEngine.dispatchAction defensively: expose `var confirmListener: ((String, (Boolean) -> Unit) -> Unit)?` and, when `confirm` is present and a listener is installed, defer the whole body of dispatchAction into the listener's callback. Add a regression test asserting that a `confirm` descriptor produces no `event.action` frame and no queue record until the confirm callback returns true, and none at all when it returns false.

**Verdicts:**
- `CODE TRUTH` refuted=False (high): Reproduced by reading. SPEC.md:1260 "When `confirm` is present, the Companion MUST present the exact confirmation before creating, persisting, or delivering the event. Declining MUST be a clean no-op." A repo-wide `grep -rn confirm --include=*.kt --include=*.el .` (minus Compose `confirmButton`/`confirmValueChange`) yields exactly four production hits: SpecValidator.kt:907-911 (type-check only: no
- `SPEC TEXT` refuted=False (high): SPEC.md:1260-1263 carries the quoted sentence byte-for-byte in §14.1 running prose (not the informative JSON example at 1210-1219), and §2.1 makes unmarked prose normative: "When `confirm` is present, the Companion MUST present the exact confirmation before creating, persisting, or delivering the event. Declining MUST be a clean no-op." Three MUSTs, subject is "the Companion" (the indicted Kotlin 
- `MATERIALITY` refuted=False (high): SPEC.md:1260 "When `confirm` is present, the Companion MUST present the exact confirmation before creating, persisting, or delivering the event." The path is live and unguarded: SpecValidator.kt:907-912 accepts `confirm` (and SurfaceStoreTest.kt:355-358 asserts a queue+ttl_s+confirm descriptor is accepted, so no prior gate rejects it), Vocabulary.kt:69 lists it as a legal remote member, and Compan

## [P1] [unverified] §14.1 (via §18.5) — Notification action `on_tap.confirm` is validated but never presented — a destructive action fires on one shade tap

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/ContextlessEvents.kt`:38  
**SPEC line:** 1260  
**Auditor:** Audit SS18.5 (notification surfaces: meta, priority monotonicity amend

**SPEC quote:**
> When `confirm` is present, the Companion MUST present the exact confirmation before creating, persisting, or delivering the event. Declining MUST be a clean no-op. The Companion MUST NOT defer this confirmation until replay and MUST NOT infer confirmation text from a newer surface.

**Detail:** §18.5 requires each notification action's `on_tap` to be a remote ActionDescriptor, so the full §14.1 descriptor vocabulary — including `confirm` — is legal there (Vocabulary.kt:69 lists `confirm` in the remote row; SpecValidator.kt:907-911 accepts it as a non-empty string; validateNotificationAction, SpecValidator.kt:230-301, passes it through untouched). The tap path is NotificationActionReceiver.onReceive (Notifications.kt:303-332) -> routeNotificationAction (ContextlessEvents.kt:114-143) -> dispatchContextless (ContextlessEvents.kt:38-82). dispatchContextless never reads `confirm`: it builds `params`, checks max_event_bytes, and goes straight to queue.admit / deliverLiveDrop. No confirmation UI exists anywhere in the tap path — grep for `"confirm"` across companion/wire and companion/app main sources returns only Vocabulary.kt:69, SpecValidator.kt:907-911, and unrelated Compose `confirmButton` lambdas. The identical gap exists on the app-surface path (DeviceBridge.action -> CompanionEngine.dispatchAction), but the notification case is the acute one: the tap happens in the system shade, often cold with no Activity in the foreground, so the user gets no chance to decline at all. Not a documented deferral (REWRITE-PLAN.md never mentions confirm).

**Failure scenario:** Emacs pushes `surface.update` for `notification:mail-42` with `meta.actions[0] = {label:"Delete", on_tap:{action:"mail.delete", args:{id:"42"}, confirm:"Delete this message permanently?", when_offline:"queue", ttl_s:3600}}`. SurfaceStore accepts it and Notifications.postSurface renders a "Delete" button. The user brushes the button in the shade; NotificationActionReceiver immediately routes it and dispatchContextless calls queue.admit(), durably persisting the mail.delete occurrence. "Delete this message permanently?" is never shown and there is no way to decline — the exact single-tap destructive dispatch that `confirm` exists to prevent.

**Proposed fix:** Thread `confirm` through the tap path: carry `on_tap.confirm` in the NotificationActionReceiver intent extras and, when present, have the receiver launch a confirmation Activity (or full-screen/heads-up confirm surface) and call routeNotificationAction only after the user accepts; a decline must be a clean no-op that neither creates an event nor dismisses the notification. Fix the app/dialog path symmetrically by gating CompanionEngine.dispatchAction on a host confirm hook before any event is constructed.

## [P1] [CONFIRMED] §14.3 — `dialog.submit` on a `text_input.on_submit` — the one builtin §14.3 permits on a value-producing hook — is a silent no-op that leaves the dialog request outstanding forever

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt`:250  
**SPEC line:** 1314  
**Auditor:** Audit SS14.1 through SS14.3 (ActionDescriptor shape, the dotted action

**SPEC quote:**
> The injection table applies to remote ActionDescriptors. Every hook listed in
the table MUST use a remote descriptor, except that `on_submit` inside a dialog
MAY use the `dialog.submit` builtin. That exception performs no implicit value
injection; it MUST use the builtin's authored `value` or `capture_fields` when
the submitted value is required.

**Detail:** Only button-shaped nodes route dialog builtins through DialogContext: `onButton` (Renderer.kt:525-548) special-cases `dialog.submit`/`dialog.dismiss` when `ctx.dialog != null`, and it is called from RenderButton/RenderIconButton/RenderChip/RenderAssistChip/RenderMenu (InputNodes.kt:76, 99, 122, 136, 169). RenderTextInput.submit (Renderer.kt:250-261) does not use onButton — it calls `ctx.actionWithFields(onSubmit, ...)` for a password and `ctx.action(onSubmit, v)` otherwise. Both land in DeviceBridge (DeviceBridge.kt:150/173) → CompanionEngine.dispatchAction, whose first line (CompanionEngine.kt:255) is `if (descriptor.has("builtin")) return executeBuiltin(surface, descriptor)`. executeBuiltin (CompanionEngine.kt:207-241) has cases for `view.switch`, `trigger.fire`, `clipboard.copy`, `share.send`, `companion.settings.open` and no `dialog.submit`/`dialog.dismiss` case — its own comment (lines 237-239) says "the renderer routes those through DialogContext", which is true only for buttons. The `when` falls through and returns, so nothing happens: the dialog is never completed, `completeDialogSubmit` is never called, and for a password the captured secret in `extraFields` is dropped on the floor without erasure.

**Failure scenario:** Emacs sends `dialog.show {dialog_id:"login", spec:{t:"column", children:[{t:"text_input", id:"pw", password:true, on_submit:{builtin:"dialog.submit", capture_fields:["pw"]}}]}}` — valid under §14.2 (dialog.submit MAY carry capture_fields) and explicitly blessed by §14.3. The user types the password and presses the IME Done key. submit() → actionWithFields → dispatchAction → executeBuiltin("dialog:login", {builtin:"dialog.submit"}) → no matching case → return. The dialog stays on screen, `dialogs["login"]` stays populated, the `dialog.show` request is never answered, and Emacs blocks on it until its client timeout. The user's only escape is a dismissal, which returns `{status:"dismissed"}` and loses the entered value.

**Proposed fix:** Route every dialog-context builtin through one helper. Extract the dialog-builtin branch of `onButton` into `fun dispatchInDialog(descriptor: JSONObject, ctx: RenderCtx, localValue: Any?): Boolean` that returns true when it handled a `dialog.submit`/`dialog.dismiss`, and call it first from RenderTextInput.submit() (passing the field's current text so a password can be merged into the submit `fields` map before `dialog.fields` is read), from the editor's on_save/on_enter path if those are wired, and from onButton. Also close the fall-through in CompanionEngine.executeBuiltin: add an explicit `"dialog.submit", "dialog.dismiss" ->` branch that resolves the dialog id from a `dialog:<id>` surface string and calls completeDialogSubmit/completeDialogDismiss, so a non-button host can never silently swallow the completion. Test: a dialog whose only submit path is a text_input on_submit builtin completes the outstanding request with `{status:"submitted", fields:{...}}`.

**Verdicts:**
- `CODE TRUTH` refuted=False (high): Reproduced end-to-end by reading, and found no alternate handler. (1) SPEC.md:1314-1319 is quoted verbatim and blesses `dialog.submit` on a dialog `on_submit`. (2) `text_input` IS in the dialog profile (NodeSupport.kt:46-48, `DIALOG_NODE_TYPES`), so the node renders rather than degrading. (3) SpecValidator accepts the shape: `validateAction` (SpecValidator.kt:879-956) picks `ACTION_SCHEMA["dialog.
- `MATERIALITY` refuted=False (high): The chain is reachable end to end with no gate. SPEC.md:1314-1317 explicitly permits `dialog.submit` on `on_submit` inside a dialog ("MAY use the `dialog.submit` builtin ... it MUST use the builtin's authored `value` or `capture_fields`"), SPEC.md:1298 makes that builtin REQUIRED in the dialog profile, and SPEC.md:2212-2214 makes completing the outstanding request a MUST. The Companion advertises 
- `SPEC TEXT` refuted=False (high): The quote is verbatim and normative at SPEC.md:1314-1318 (§14.3 body prose, not a note/example), and no SPEC-CHANGES.md amendment touches §14.3 or the dialog builtins. The "MAY" binds the sender; the receiver MUST is elsewhere and unambiguous: SPEC.md:2210-2214 (§18.1) "The Companion MUST ... keep the request outstanding until one of these occurs: `dialog.submit` completes it with `{status:\"submi

## [P1] [unverified] §14.5 (with §14.4, §13.1) — Notification action events omit `surface` and `revision_seen`, though a notification action originates from a surface

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/ContextlessEvents.kt`:48  
**SPEC line:** 1449  
**Auditor:** Audit SS18.5 (notification surfaces: meta, priority monotonicity amend

**SPEC quote:**
> A Companion MUST include `surface` and `revision_seen` for every event originating from a surface. It MUST NOT fabricate the latest revision after the fact; the field records what the user actually saw.

**Detail:** §13.1 makes `notification:<name>` a surface and §13.4 makes its `meta.actions[*].on_tap` part of that surface's SurfaceSpec, so a notification action tap is a surface event. §14.4 line 1383 enumerates the context-less classes exhaustively — "A trigger, reminder, shortcut, or pie-menu event MUST omit all three context members" — and notification actions are NOT in that list. The impl nevertheless routes them through the context-less path: NotificationActionReceiver (Notifications.kt:303-332) -> routeNotificationAction (ContextlessEvents.kt:114-143) -> dispatchContextless (ContextlessEvents.kt:38-82), whose params object is built at lines 48-56 from exactly {event_id, action, occurred_at_ms, args?, fields?, queued_at_ms?} — no `surface`, no `revision_seen`, ever. Notifications.buildAction (Notifications.kt:199-203) does stamp `surface` into the tap Intent, but only to address the NotificationManager cancel; it never records the accepted revision, and routeNotificationAction takes no surface parameter. NotificationActionTest.kt:37-43 pins this shape (asserting only action/args/fields), so the omission is locked in by test. Compliance is straightforward — SurfaceStore.revisionOf(surface) is available and durable at post time — so this is not a spec impossibility.

**Failure scenario:** `surface.update` accepts `notification:mail-42` at revision 42 with `meta.actions[0] = {label:"Archive", on_tap:{action:"mail.archive", when_offline:"queue", ttl_s:3600}}`. The user taps Archive. The Companion sends `event.action` with params `{event_id, action:"mail.archive", occurred_at_ms, queued_at_ms}` and no `surface`/`revision_seen`. An Emacs endpoint performing §14.5's required surface/revision validation for a surface-registered action has no context to validate against and must answer `rejected`, so every notification action tap is permanently lost; the reference ebp.el only tolerates it because ebp-client--event-context-valid-p (ebp.el:873-882) treats a missing `surface` as the global-event case.

**Proposed fix:** In Notifications.buildAction, read the accepted revision (CompanionStores.surfaces(ctx).revisionOf(surface)) at post time and put it, with `surface`, into the action PendingIntent extras. Add `surface: String?` / `revisionSeen: Long?` parameters to routeNotificationAction and dispatchContextless and emit them as `surface` / `revision_seen` when present. Do NOT read the current revision at tap time — §14.5 forbids fabricating the latest revision after the fact.

## [P1] [unverified] §14.6 (admission boundary of §15.1) — A password-bearing on_submit with when_offline:"queue" is durably admitted — the secret is written to ebp-queue.json and replayed on every reconnect

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:306  
**SPEC line:** 1518  
**Auditor:** Audit SS15 (durable queue and replay) against DurableQueue.kt, QueueSt

**SPEC quote:**
> A remote descriptor that captures a password MUST
use `when_offline: "drop"`, MUST NOT use `dedupe` or `ttl_s`, and MUST NOT create
an event unless an authenticated `READY` session exists. […] The Companion MUST hold the value only in volatile memory, place it
only in the explicitly submitted action's or dialog result's `fields`, transmit
it without durable admission, and erase its local copy as soon as the request
concludes or the interaction is cancelled. A password value MUST NOT appear in
`args`, a builtin parameter value, a retry queue, diagnostics, or crash
recovery.

**Detail:** Nothing on the accept path or the dispatch path enforces the §14.6 "password ⇒ drop" rule.

Accept time: `SpecValidator.walkNode` case "text_input" (SpecValidator.kt:408-419) only rejects a seeded `value` and an `on_change` on a password node; `validateAction` (SpecValidator.kt:880-948) validates `when_offline`/`ttl_s`/`dedupe` against the generic §14.1 rules and never consults the node's `password` flag. The deferred `captureRefs` pass (SpecValidator.kt:121-125) only checks that each capture name resolves to a stateful node — it does not reject a password capture on a non-drop descriptor either.

Dispatch time: `Renderer.kt:256` (`password -> ctx.actionWithFields(onSubmit, JSONObject().put(id, v))`) hands the cleartext secret to `DeviceBridge.actionWithFields` (DeviceBridge.kt:173-180) → `CompanionEngine.dispatchAction`, whose `extraFields` merge at CompanionEngine.kt:284 (`extraFields?.let { for (k in it.keySet()) fields.put(k, it.get(k)) }`) puts the secret into `params.fields` (line 285) unconditionally — it does not consult `surfaces.isPasswordNode`, which the engine already uses two dozen lines earlier at line 353. The `when (policy)` at line 302 then routes "queue"/"wake" to `queue.admit(params, …)` at line 306, and `DurableQueue.admit` writes the record through `persist()` (DurableQueue.kt:147) → `FileQueueStore.replace` → plaintext `ebp-queue.json` in filesDir.

Note the `capture_fields` route is safe by accident (`surfaces.currentValue` returns null for a password because `SurfaceStore.putDraft` refuses password drafts at SurfaceStore.kt:251, so `fields.<id>` would be JSON null); it is the renderer-supplied `extraFields` route that leaks, and it needs no `capture_fields` member at all.

**Failure scenario:** Emacs sends `surface.update` for `app:vault` containing `{"t":"text_input","id":"pw","password":true,"on_submit":{"action":"vault.unlock","when_offline":"queue","ttl_s":3600}}`. SpecValidator accepts it. The user types "hunter2" and presses Done while the transport is down. `dispatchAction` builds `params.fields = {"pw":"hunter2"}`, policy is "queue", so `queue.admit` commits the record and `FileQueueStore` fsyncs `{"records":[{"event":{…"fields":{"pw":"hunter2"}…},"policy":"queue","expires_at_ms":…}],…}` to `filesDir/ebp-queue.json`. The cleartext password now survives process death, device reboot, and ADB backup for up to ttl_s (3600 s here; up to 604800 s is legal), and is re-sent on every reconnect until Emacs answers with a permanent status.

**Proposed fix:** Two layers. (1) In `SpecValidator`, after the document walk (beside the existing `captureRefs` resolution loop, SpecValidator.kt:121-125), reject any remote descriptor whose `when_offline` is not "drop" — or which carries `dedupe`/`ttl_s` — when it is the `on_submit`/`on_change` hook of a node with `password: true` or when its `capture_fields` names such a node; collect the (descriptor path, hook-owner node) pairs during the walk the same way `captureRefs` is collected. (2) Defence in depth in `CompanionEngine.dispatchAction`: before the `when (policy)` at line 302, if any key merged from `extraFields` (or named in `capture_fields`) is a `surfaces.isPasswordNode(surface, k)`, force the drop path — i.e. `if (state != READY) { erase fields; callback(null, 1201 content-invalid); return }` and never reach `queue.admit`.

## [P1] [CONFIRMED] §14.6 (governed from §14.1 "Section 14.6 adds stricter rules for passwords") — A password-bearing submission is admitted to the durable queue: nothing enforces when_offline=drop for a descriptor that captures a password

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:306  
**SPEC line:** 1516  
**Auditor:** Audit SS14.1 through SS14.3 (ActionDescriptor shape, the dotted action

**SPEC quote:**
> A node with `password: true` MUST NOT emit `state.changed`. Its value MUST NOT
be written to disk, included in `input_state`, logged, or retained after the
containing interaction ends. A remote descriptor that captures a password MUST
use `when_offline: "drop"`, MUST NOT use `dedupe` or `ttl_s`, and MUST NOT create
an event unless an authenticated `READY` session exists.

**Detail:** No layer cross-checks a password node against its submitting descriptor's offline policy. (a) SpecValidator.validateNode's text_input case (SpecValidator.kt:408-420) rejects only a seeded password value and an `on_change`; a password `on_submit` with `when_offline:"queue"` and `ttl_s` passes. (b) SpecValidator.validateAction (879-956) validates the policy/ttl_s/dedupe cross-rules but has no knowledge of the node it hangs off, and the deferred capture_fields resolution (SpecValidator.kt:121-125) checks only that each name is in `ctx.statefuls` — it never inspects `password`. `grep -n password SpecValidator.kt` shows the only password checks are the reset_input_ids gate (142) and the seed gate (416). (c) At dispatch, Renderer.RenderTextInput.submit (Renderer.kt:250-258) sends a password's on_submit through `ctx.actionWithFields(onSubmit, JSONObject().put(id, v))` — the secret is placed in `fields` unconditionally, whether or not the descriptor names the node in `capture_fields`. (d) CompanionEngine.dispatchAction merges extraFields into `params.fields` (line 284) and then branches on `policy` at line 302, calling `queue.admit(params, policy, dedupe, ttl_s)` at line 306. DurableQueue.admit (DurableQueue.kt:111-155) wraps the complete params in a record and calls persist() → QueueStore.replace, writing the record to disk. There is no password predicate anywhere on that path.

**Failure scenario:** Emacs pushes `app:login` with `{t:"text_input", id:"pw", password:true, on_submit:{action:"auth.login", when_offline:"queue", ttl_s:3600, capture_fields:["pw"]}}` (accepted: no seeded value, no on_change). The device is offline. The user types `hunter2` and presses Done. RenderTextInput.submit → actionWithFields → dispatchAction with policy `queue` → queue.admit persists `{event:{action:"auth.login", fields:{pw:"hunter2"}, ...}, policy:"queue", expires_at_ms:...}` into the app's queue file. The plaintext password is now on disk, survives process death, is replayed after reconnect, and is retained for up to 3600 s — violating "MUST use when_offline: drop", "MUST NOT use ttl_s", "MUST NOT create an event unless an authenticated READY session exists", and "MUST NOT be written to disk".

**Proposed fix:** Two gates. (1) Validation: in SpecValidator, make the deferred capture_fields pass password-aware — when a resolved stateful node has `password:true`, require the capturing descriptor to be either a `dialog.submit` builtin or a remote descriptor whose effective `when_offline` is `drop` with no `dedupe`/`ttl_s`, else `ContentInvalid`. This needs the descriptor object (not just its path) carried in `Ctx.captureRefs`, e.g. `captureRefs: MutableList<Triple<String, JSONObject, List<String>>>`. Additionally, in validateNode's `text_input` case, reject `password:true` whose `on_submit` is a remote descriptor with `when_offline != "drop"` (or that carries `dedupe`/`ttl_s`), since the renderer submits the secret through that hook regardless of capture_fields. (2) Defense in depth at dispatch: give dispatchAction an `extraFields != null` (secret-bearing) flag that forces the `drop` branch, refuses to dispatch unless `state == SessionState.READY`, and never reaches queue.admit. Add tests: a queue-policy password on_submit is 1201 at surface.update, and dispatchAction with extraFields on a `queue` descriptor writes no queue record.

**Verdicts:**
- `CODE TRUTH` refuted=False (high): Reproduced by reading. SPEC.md:1516-1526 puts the duty on the Companion directly ("transmit it without durable admission", "MUST NOT be written to disk", "A password value MUST NOT appear in ... a retry queue"), so it is not merely an authoring rule. Code: SpecValidator.kt:415-418 is the only password gate in the text_input case (`if (node.optBoolean("password") && (value is String && value.isNotE
- `MATERIALITY` refuted=False (high): The scenario survives every materiality test. (1) Spec duty is on the Companion, not the peer: SPEC.md:1681-1684 "The Companion MUST validate an entire SurfaceSpec before accepting its surface revision. A malformed node, invalid required field, invalid action descriptor ... MUST reject the entire update with 1201 content-invalid" — a password-capturing descriptor with when_offline:"queue"+ttl_s IS
- `SPEC TEXT` refuted=False (high): SPEC.md:1518-1520 is verbatim, normative §14.6 prose (no MAY/SHOULD, not a note or example): "A remote descriptor that captures a password MUST use `when_offline: \"drop\"`, MUST NOT use `dedupe` or `ttl_s`, and MUST NOT create an event unless an authenticated `READY` session exists." It is not scoped to Emacs alone — the same paragraph binds the Companion directly at SPEC.md:1523-1528 ("The Compa

## [P1] [unverified] §16.1 / §17.3 — Presentation-identity state (collapsible expansion, tabs selection) is lost whenever a sibling is inserted, because child render loops emit no Compose `key` for the §16.1 identity path

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt`:190  
**SPEC line:** None  
**Auditor:** Audit SS16 (UI document model) — SS16.1 node identity and the identity

**SPEC quote:**
> Tree-path identity is unstable under insertion;
Emacs SHOULD supply a `key` or `id` for any node whose local presentation state
should survive a snapshot replacement.

Presentation identity controls focus, expansion, selection, scroll anchors,
and similar rendering state.  ...  `collapsible.collapsed` is boolean and defaults to `false`. It seeds only the
first snapshot for a new presentation identity. The Companion MUST preserve
the user's current expansion state across later snapshots with the same
Section 16.1 presentation identity, regardless of a repeated authored
`collapsed` value.  ...  The Companion MUST preserve the selected
index across snapshots with the same Section 16.1 presentation identity

**Detail:** `RenderCtx.child()` builds the §16.1 identity path correctly (Attributes.kt:77 `identityPath`, key > id > tree path), and `RenderCollapsible` keys its expansion on it (`rememberSaveable(ctx.path)`, LayoutNodes.kt:357) while `RenderTabs`/`RenderMonthGrid` wrap in `key(ctx.path)` (LayoutNodes.kt:401, VisualizationNodes.kt:267). But the identity path is only ever used as a *remember input*, never as a Compose group key at the point where children are emitted. `RenderChildren` (Renderer.kt:187-192), `RenderRowChildren` (200-207) and `RenderColumnChildren` (210-217) all iterate `for (i in 0 until children.length()) { RenderNode(child, ctx.child(child, i), m) }` with no `key(...)` wrapper. Compose matches repeated invocations of one call site positionally, so when a snapshot inserts a sibling before an existing child, invocation #0 now runs the *new* node through `RenderNode`'s `when (type)` (Renderer.kt:133). A different `when` branch is a different group key, so the composer disposes the stored subtree — including the collapsible's `expanded` state and the `key(ctx.path)` group inside tabs — and composes a fresh one, re-seeding from the authored `collapsed`/`initial`. The identity path is unchanged (`.../k:sec`), so this is exactly the same-identity case §17.3 says MUST be preserved. The renderer already has the correct machinery and applies it in exactly one place: `RenderLazyColumn` passes `lazyChildKeys()` to `items(key = ...)` (LayoutNodes.kt:243,251), which makes lazy children movable — every non-lazy container (column, row, box, flow_row, card, collapsible children, tabs pages, scaffold slots) lacks it.

**Failure scenario:** Snapshot 1 (rev 1) on app:main: `{"t":"column","children":[{"t":"collapsible","id":"sec","collapsed":true,"header":{"t":"text","text":"Today"},"children":[...]}]}`. The user taps the header and expands it. Snapshot 2 (rev 2) prepends a banner: `{"t":"column","children":[{"t":"text","text":"3 new"},{"t":"collapsible","id":"sec","collapsed":true,...}]}` — same `id`, so the same §16.1 presentation identity. Observed: the collapsible snaps shut (re-seeded from `collapsed:true`), losing the user's expansion. Identical scenario with `{"t":"tabs","id":"t","initial":0,...}` on page 2 resets to page 0 on any prepended sibling.

**Proposed fix:** Wrap each child emission in the identity path so Compose can move the group instead of disposing it: in `RenderChildren`/`RenderRowChildren`/`RenderColumnChildren` compute `val p = identityPath(ctx.path, child, i)` and emit `key(p) { RenderNode(child, RenderCtx(surface, bridge, dialog, p), m) }`. Apply the same to the fixed-slot `RenderNode(...)` calls in `RenderScaffold`, `RenderCard`, `RenderTabs` pages and `RenderCollapsible.header`. Add a Compose UI test (or a Robolectric one) that expands a collapsible, prepends a sibling, and asserts it is still expanded.

## [P1] [unverified] §16.1 / §17.3 — Presentation identity for an `id`-bearing node is composed with its ancestor tree path, so collapsible expansion and tabs selection are lost whenever an ancestor's index shifts

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Attributes.kt`:77  
**SPEC line:** None  
**Auditor:** Audit SS17.4 through SS17.6 (layout nodes, the scaffold and its slots,

**SPEC quote:**
> A node's presentation identity is its `key` when present, otherwise its `id` when present, otherwise its structural tree path. A `key` MUST be unique among siblings. Every authored node `id` MUST be unique across the complete surface or dialog document, including input-stateful, collapsible, tabs, and editor nodes. … The Companion MUST preserve the user's current expansion state across later snapshots with the same Section 16.1 presentation identity, regardless of a repeated authored `collapsed` value. … The Companion MUST preserve the selected index across snapshots with the same Section 16.1 presentation identity; a new identity resets to `initial`.

**Detail:** §16.1 makes an `id`-bearing node's presentation identity the id ALONE — ids are document-unique precisely so the identity is position-independent. `identityPath` (Attributes.kt:77-85) instead returns `"$parentPath/id:$id"`, i.e. it prefixes the id with the ancestor chain, and only a `key`ed/`id`ed ancestor contributes a stable segment; an unkeyed ancestor contributes `"/$i:${t}"` (line 83). RenderCollapsible keys expansion on that path (`rememberSaveable(ctx.path) { mutableStateOf(!collapsed) }`, LayoutNodes.kt:357) and RenderTabs keys the pager on it (`key(ctx.path)`, LayoutNodes.kt:401). When any unkeyed ancestor's sibling index changes, every descendant path changes, `rememberSaveable`'s inputs change, and the state re-seeds from the authored `collapsed`/`initial` even though the §16.1 identity (the id) never changed. A second, independent manifestation: RenderChildren / RenderRowChildren / RenderColumnChildren (Renderer.kt:187, 200, 210) emit children in a bare `for` loop with no Compose `key()`, so remembered state is bound to the loop SLOT, not to the node. Insert one sibling above a keyed collapsible and slot i now composes authored child i-1; its `rememberSaveable(ctx.path)` sees inputs change from the former occupant's path to this node's path and re-initialises. The same shift discards the `key(ctx.path)` group inside RenderTabs, resetting the pager to `initial`. The impl already applies the correct pattern for lazy containers (`lazyChildKeys` + `key = { keys[it] }`, LayoutNodes.kt:244/251, and `key = { pos -> itemKey(order[pos]) }` at 642) — the non-lazy containers simply omit it.

**Failure scenario:** v1: `scaffold.body = {t:column, children:[{t:column, children:[{t:collapsible, id:"notes", collapsed:true, header:…, children:…}]}]}`. The user expands `notes`. v2 (same surface, same ids) inserts a banner: `{t:column, children:[{t:text,…}, {t:column, children:[{t:collapsible, id:"notes", collapsed:true, …}]}]}`. The inner column's path goes `/1:column/0:column` → `/1:column/1:column`, so the collapsible's path goes `.../0:column/id:notes` → `.../1:column/id:notes`; `rememberSaveable` re-initialises and the section snaps shut, discarding the user's expansion even though its §16.1 identity (`notes`) is unchanged. The same edit resets a `tabs` node's selected page to `initial`.

**Proposed fix:** In `identityPath`, return an ancestor-independent identity for an id-bearing node (`"id:$id"`, valid because §16.1 makes ids document-unique) and keep `"$parentPath/k:$key"` / `"$parentPath/$i:$t"` for the key and tree-path cases. Additionally wrap each child emission in `key(identityPath(...)) { RenderNode(...) }` inside RenderChildren/RenderRowChildren/RenderColumnChildren so Compose moves the child's slot state with the node instead of re-binding it positionally.

## [P1] [unverified] §17.4 — clear_on_submit clears the field unconditionally at submit time, destroying the value on an offline drop or admission failure

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt`:260  
**SPEC line:** 1998  
**Auditor:** Audit SS17.1 through SS17.3 (the node-type vocabulary preamble, conten

**SPEC quote:**
> For a non-password text input whose `on_submit` is remote, `clear_on_submit: true` MUST clear the value only after that occurrence is safely admitted under Section 14.4. The Companion MUST retain the value after an offline `drop`, admission failure, `stale` or `rejected` result, transient error, cancellation, timeout, or transport loss.

**Detail:** `RenderTextInput.submit()` (Renderer.kt:250-261) dispatches the occurrence and then clears synchronously and unconditionally: line 257 `ctx.action(onSubmit, v)` -> `RenderCtx.action` (Renderer.kt:79) -> `DeviceBridge.action` (DeviceBridge.kt:150) which only *posts* the work onto `dispatchExecutor` and supplies a callback that is used solely to surface queue errors to `onQueueProblem`. Line 260 then runs `if (node.optBoolean("clear_on_submit")) value = ""` on the Compose main thread, before the executor has even run, and with no knowledge of the §14.4 outcome. There is no admission signal plumbed back to the renderer at all: `DeviceBridge.action/actionInjecting/actionWithFields` are fire-and-forget and the engine's `dispatchAction` result is discarded. Every one of the seven retain-cases the SPEC enumerates (drop, admission failure, stale, rejected, transient error, cancellation, timeout, transport loss) therefore clears the field. Note the W9 audit's I2 fix note said "honor clear_on_submit per §14.4"; the remediation added the clear but not the §14.4 gate.

**Failure scenario:** Emacs pushes `{"t":"text_input","id":"title","clear_on_submit":true,"on_submit":{"action":"note.capture"}}` (no `when_offline`, so the §14.1 default `drop` applies). The transport is down (state != READY). The user types "Buy milk for Tuesday" and presses the IME Done key. `submit()` posts the descriptor, the engine drops the occurrence because the policy is `drop` and there is no session, and line 260 immediately sets the field to "". The user's text is destroyed and was never delivered — exactly the case the SPEC's retain list names first.

**Proposed fix:** Thread an admission outcome back from `CompanionEngine.dispatchAction` through `DeviceBridge.action` to the renderer (the callback slot already exists), and only clear when the result is a safe §14.4 admission (delivered in READY, or durably queued). Keep the value on drop/stale/rejected/error/cancel/timeout/transport loss. Reject `clear_on_submit:true` at validation when `on_submit` is absent, since there is then nothing to admit.

## [P1] [unverified] §18.1 — Remote actions authored inside a dialog are never dispatched — no code path emits an event.action carrying dialog_id

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:256  
**SPEC line:** 2235  
**Auditor:** Audit SS18.1 through SS18.3 (dialogs incl. the dialog.show request and

**SPEC quote:**
> A remote action inside a dialog uses `event.action.dialog_id` and MAY use its own `capture_fields`. Every such remote ActionDescriptor MUST set or default `when_offline` to `drop`; `queue` and `wake` are invalid because a dialog has no durable instance identity.

**Detail:** Call chain for a non-builtin on_tap inside a dialog: Renderer.kt:547 `ctx.action(onTap)` -> RenderCtx.action (Renderer.kt:78-79) `bridge.action(surface, descriptor, value)` where `surface` was set to the synthetic string "dialog:$dialogId" by RenderDialogRoot (Renderer.kt:115) -> DeviceBridge.action (DeviceBridge.kt:150-158) -> CompanionEngine.dispatchAction (CompanionEngine.kt:251). Line 256 is `val revision = surfaces.revisionOf(surface) ?: return`; SurfaceStore.revisionOf (SurfaceStore.kt:86-87) looks up `records["dialog:rename"]`, which never exists because a dialog is deliberately not registered in the surface store. The function returns silently. `grep -rn dialog_id --include=*.kt` over the whole companion tree shows the only producer-side occurrences are `params.opt("dialog_id")` in handleDialogShow and comments; nothing ever WRITES `dialog_id` into an event.action params object. dispatchDescriptorContextless (CompanionEngine.kt:826) is the only other event path and it deliberately omits all three context members (§14.4 pie/reminder shape), so it cannot serve dialogs either. §14.4 line 1382 pins the required shape: "A dialog event MUST contain `dialog_id` and MUST omit `surface` and `revision_seen`." The Emacs endpoint already implements the receiving half (ebp.el:873-882 `ebp-client--event-context-valid-p` accepts a dialog-only context), so the gap is one-sided. This was raised as W7 finding at docs/AUDIT-w7-conformance.md:152 and is still unfixed in the current tree (git log shows only the P1 batch and amendments 40-42 were remediated).

**Failure scenario:** Emacs sends dialog.show {dialog_id:"search", spec:{t:"column",children:[{t:"text_input",id:"q"},{t:"button",label:"Search",on_tap:{action:"note.search",capture_fields:["q"]}}]}}. The dialog renders (button is in DIALOG_NODE_TYPES, NodeSupport.kt:46-48) and the spec validates. The user types a query and taps Search: onButton falls through to ctx.action(onTap), dispatchAction returns at line 256, and NO frame is written. Emacs receives nothing, the dialog stays on screen and outstanding, and the user has no feedback. Every dialog whose interaction model is a remote action rather than dialog.submit is completely inert.

**Proposed fix:** Add a dialog dispatch path in CompanionEngine (e.g. `dispatchDialogAction(dialogId, descriptor, hookValue, dialogLocalFields)`) that builds event.action params with `dialog_id` set and `surface`/`revision_seen` omitted, forces when_offline=drop (never queue.admit), resolves capture_fields against the renderer's dialog-local field map, and enforces max_event_bytes exactly as dispatchAction does. Give RenderCtx a dialog-aware `action()` that routes to it instead of bridge.action("dialog:<id>", ...).

## [P1] [unverified] §19 — Editor sessions are never re-opened after reconnection: a surviving synchronized editor stays permanently unsynchronized

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:434  
**SPEC line:** 2458  
**Auditor:** Audit SS17.7 (editor toolbar: snippets, substitution tokens, placement

**SPEC quote:**
> Transport loss closes all editor sessions locally; both endpoints MUST treat their session IDs as dead and create new sessions after reconnection.  … An accepted update during the next `SYNCING` phase replaces that volatile text and explicitly seeds the forthcoming session. If no such update arrives, the fresh session uses the currently displayed volatile shadow or cached authored value. `edit.open.text` MUST equal that selected seed exactly.

**Detail:** `close()` (CompanionEngine.kt:146-149) clears `editors`, `surfaceEditors` AND `pendingEditors`. The only two places a session is ever created are `reconcileEditors` (line 638, reached only from `handleSurfaceUpdate` line 602 when a surface.update is APPLIED) and the `session.ready` flush of `pendingEditors` (line 432-435) — which was emptied by `close()`. Surfaces themselves are durable across connections (`SurfaceStore` is a process-wide singleton injected by DeviceBridge.kt:43, and DeviceBridge.serve():237 builds a FRESH `CompanionEngine` per socket), and §13.5 requires the Companion to keep rendering the cached snapshot while disconnected. So on a reconnect where Emacs reconciles the welcome `surfaces` map and re-pushes nothing (§10 line 739: 'Emacs reconciles cached surfaces and input state'), the editor node is still on screen with no session, no `edit.open`, and no path that will ever create one. The §19 sentence at line 2447 ('If no such update arrives, the fresh session uses the currently displayed volatile shadow or cached authored value') explicitly contemplates exactly this case and requires a fresh session anyway.

**Failure scenario:** Emacs pushes app:notes rev 5 containing {t:editor,id:body,document:doc:1,value:"..."}; session READY -> edit.open sent, user edits mirror fine. The socket drops (engine.close clears surfaceEditors/pendingEditors). Emacs reconnects; the welcome reports {app:notes:5}, which matches Emacs's own revision, so it pushes no surface.update and sends session.ready. State is READY, the editor is still rendered from the durable store, but no edit.open is ever emitted. The user types: Renderer.commit -> bridge.editorEdit -> engine.localEditorEdit -> `editors[document to editorId] ?: return false` (line 1137) — every keystroke is silently dropped, forever, with no diagnostic. Emacs's buffer and the on-screen document diverge without either side noticing.

**Proposed fix:** On entering READY (CompanionEngine.kt:432, after the state.changed flush), re-scan every present surface in the store — `surfaces.present()`/`surfaces.spec(s)` through the same `scanSyncedEditors` walk — and, for every synchronized-editor identity not already in `editors`, open a fresh session seeded per §19 line 2445-2449 (host volatile shadow if the process survived, else the cached authored `value`), re-populating `surfaceEditors`. Add an EditorLifecycleTest that closes the engine, builds a second engine on the same SurfaceStore, drives it to READY with no surface.update, and asserts one edit.open with text == the cached seed.

## [P1] [unverified] §19.4 — Inbound edit.apply never reaches the rendered field; the §19.4 'editor text still equals its shadow' gate is unimplemented, so the next local edit corrupts the document

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt`:318  
**SPEC line:** 2655  
**Auditor:** Audit SS17.7 (editor toolbar: snippets, substitution tokens, placement

**SPEC quote:**
> The Companion MUST apply a text-changing form only when:

- `seq` is exactly one greater than its current sequence;
- the current editor text still equals its synchronized shadow;
- the splice and resulting length are valid; and
- no platform text-composition transaction would be corrupted.

**Detail:** `editorListener` is the sole hook the engine fires when an accepted `edit.apply` or `edit.resync` changes the shadow (CompanionEngine.kt:1229, 1248). Grep across companion/app and companion/wire main sources finds no assignment to it — DeviceBridge.serve() wires surfaceListener, hostBuiltinListener, dialogListener, pieMenuListener, themeListener, but never editorListener. RenderEditor's field state (Renderer.kt:318-321 `rememberSaveable(... TextFieldValue(node.optString("value")))`) is seeded once and thereafter mutated only by local typing. Consequently (a) the second §19.4 gate is never evaluated — nothing compares the host field to `EditorSession.shadow`; `handleEditApply` (CompanionEngine.kt:1241) checks only seq + splice validity — and (b) the local-edit path computes its splice from the STALE field text: Renderer.kt:341 `EditorSession.diff(old, new.text)` diffs the displayed text, then `localEditorEdit` applies those offsets to a shadow that has already moved. (Also raised as an unremediated item in docs/AUDIT-w7-conformance.md; verified still open at HEAD c5165e5.)

**Failure scenario:** Shadow and field both "hello world", seq 0. Emacs sends edit.apply {seq:1,start:0,del:6,text:"",len:5,cursor:0} (delete the first word) -> gate passes, shadow becomes "world", response {applied,1}; the OutlinedTextField still displays "hello world". The user types "!" at the end of what they see: diff("hello world","hello world!") = (11,0,"!") -> splice(11,0,"!") against the 5-scalar shadow -> `start + del > n` fails, so localEditorEdit returns false and the keystroke vanishes. Worse, for an insertion at index <= 5 (e.g. typing at display offset 3): diff yields (3,0,"x"), applied to "world" -> shadow "worxld", and edit.delta {start:3,del:0,text:"x"} is sent, so the Emacs buffer receives an edit at a position the user never touched while the screen shows "helxlo world".

**Proposed fix:** Wire `engine.editorListener` in DeviceBridge.serve() to a per-(document,editor_id) callback that pushes the new shadow/cursor into the RenderEditor state (a bridge-held StateFlow keyed by document+id that RenderEditor collects), replacing the TextFieldValue text and clamping the selection; and make the local path authoritative-safe by having `localEditorEdit` take the host's pre-edit text and reject (rather than splice) when it does not equal `s.shadow`, which is the literal §19.4 gate.

## [P1] [unverified] §21.3 / §21.5 — A `time.at_ms` occurrence blocked by its gate (or by a full queue) re-arms an immediate RTC_WAKEUP alarm forever

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/TriggerAlarms.kt`:39  
**SPEC line:** 3008  
**Auditor:** Audit SS21 (device trigger module) end to end — SS21.1 trigger.set rep

**SPEC quote:**
> The Companion MUST reject a malformed gate atomically. Evaluation MUST
terminate and MUST perform no polling or unbounded work.

**Detail:** `TimeAlarmReceiver.onReceive` (TriggerAlarms.kt:47-62) calls `fireScheduled(identity, tid)` and then unconditionally `TriggerAlarms.reschedule(app)`. `reschedule` arms one alarm per entry returned by `TriggerFiringService.timeSchedule()` (TriggerFiringService.kt:110-123), whose one-shot branch is `params.has("at_ms") -> if (reg.oneShotCompleted) null else params.getLong("at_ms")` (line 116). `oneShotCompleted` is set ONLY inside the `commit` closure of `TriggerRuntime.tryAdmit` (TriggerRuntime.kt:277-278), which never runs when step-1 eligibility fails (`if (!allHold(reg.entry.getJSONArray("when"))) return`, TriggerRuntime.kt:241) or when the durable transaction fails (`else -> Unit` on QueueFull/StorageFailed, TriggerFiringService.kt:183, and the oversize-event `return` at line 162). `fireScheduled` has an anti-spin cursor advance, but it is guarded by `params.has("every_s")` (TriggerRuntime.kt:179) — the every_s spin (prior audit P2-1, fixed in RA-6 `315d4a3`) was closed, the identical at_ms case was not. So: alarm fires -> not admitted -> `timeSchedule()` still reports the same past `at_ms` -> `am.setExactAndAllowWhileIdle(RTC_WAKEUP, <past>, pi)` (TriggerAlarms.kt:39), which AlarmManager triggers immediately -> loop. Nothing bounds the iteration count or rate.

**Failure scenario:** With the reference Android profile (trigger_types = battery.level/boot/time/timezone.changed, state_types = battery.level) Emacs registers `{"id":"digest","type":"time","params":{"at_ms":<today 03:00>},"when":[{"type":"time.window","after":"09:00","before":"17:00"}],"policy":"drop"}`. At 03:00 the alarm fires; `allHold` returns false (03:00 is outside the window); `oneShotCompleted` stays false; the receiver re-arms the alarm at 03:00 (past) and AlarmManager fires it again immediately. The device runs a hot RTC_WAKEUP + background-executor loop from 03:00 until 09:00 (six hours), draining the battery. The same loop is永 permanent for a `queue`-policy one-shot when the durable queue is at `max_queued_events`: QueueFull -> no commit -> re-arm -> fire -> QueueFull, with no exit until the queue drains.

**Proposed fix:** Give `fireScheduled` the same cursor the every_s branch has for the at_ms case: when the alarm for a one-shot elapsed but the occurrence was not admitted, record a durable `lastAttemptMs`/backoff on the Registration and have `timeSchedule()` return `max(at_ms, lastAttemptMs + retryFloor)` instead of the raw `at_ms`, so re-evaluation is rate-limited (e.g. no more than once per minute) rather than immediate. Add a JVM test: a one-shot whose `when` is false at its due instant must not cause `timeSchedule()` to keep reporting an already-elapsed due time after `fireScheduled` returns.

## [P1] [unverified] §23.3 / §14.6 — A `password: true` value is durably written to plaintext disk when its `on_submit` uses `when_offline: "queue"`/`"wake"` — the validator never correlates `capture_fields` with password nodes

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:303  
**SPEC line:** 1516  
**Auditor:** Audit SS22 (capability registry and load management: traffic classes, 

**SPEC quote:**
> A node with `password: true` MUST NOT emit `state.changed`. Its value MUST NOT be written to disk, included in `input_state`, logged, or retained after the containing interaction ends. A remote descriptor that captures a password MUST use `when_offline: "drop"`, MUST NOT use `dedupe` or `ttl_s`, and MUST NOT create an event unless an authenticated `READY` session exists. … The Companion MUST hold the value only in volatile memory, place it only in the explicitly submitted action's or dialog result's `fields`, transmit it without durable admission, and erase its local copy as soon as the request concludes or the interaction is cancelled.

**Detail:** `SpecValidator.validateAction` (SpecValidator.kt:879-957) validates `when_offline`/`ttl_s`/`dedupe`/`capture_fields` with no knowledge of whether any named node has `password: true`; `validateNode`'s text_input branch (:406-418) rejects only a seeded `value` and an `on_change`, never a durable `on_submit`. Password `text_input`s ARE registered as stateful (:563-568, `text_input` is in `STATEFUL_NODE_TYPES`), so `capture_fields: ["pw"]` resolves cleanly at :120-125 — which is exactly what §14.3 (SPEC.md:1345-1349) REQUIRES the sender to author for a password submission. At render time `RenderTextInput` routes the secret through `ctx.actionWithFields(onSubmit, {id: v})` (Renderer.kt:256) → `DeviceBridge.actionWithFields` (:173-180) → `CompanionEngine.dispatchAction(..., extraFields)`, which merges the real secret into `params.fields` at :284. `dispatchAction` then reads the descriptor's policy at :286 and, for `queue`/`wake`, calls `queue.admit(params, …)` at :306. `DurableQueue.admit` persists the whole `params` object (:116-148) through `FileQueueStore.replace`, which writes it as plain JSON text to `filesDir/ebp-queue.json` (QueueStore.kt:52-73). The `drop` branch at :330-331 correctly requires READY, but nothing on the durable branch does. Note the `capture_fields` copy at :274-280 is harmless on its own (SurfaceStore never retains a password draft, so `currentValue` yields JSON null); the leak is entirely the `extraFields` path, and it is the only path by which a password can be submitted from an `app:*` surface.

**Failure scenario:** Emacs pushes `surface.update app:login` with spec `{t:"column",children:[{t:"text_input",id:"pw",password:true,on_submit:{action:"auth.login",when_offline:"queue",ttl_s:604800,dedupe:"login",capture_fields:["pw"]}}]}`. SpecValidator accepts it (no password/policy correlation). The user types `hunter2` and presses Done. `dispatchAction` takes the `"queue"` branch and `ebp-queue.json` on the device now contains `{"event":{…,"fields":{"pw":"hunter2"},…},"policy":"queue","expires_at_ms":…,"dedupe":"login"}` in cleartext, surviving process death and device reboot for up to 7 days, replayed to whatever authenticates next, and counted in the welcome's `queued_events`. Every clause quoted above is violated: written to disk, durably admitted, retained after the interaction ends, created without a READY session, and carrying both `dedupe` and `ttl_s`.

**Proposed fix:** Two layers. (1) In `SpecValidator`, record password node IDs in `Ctx` during `validateNode` and, in the post-walk `captureRefs` resolution (:119-125), reject with 1201 any descriptor that names a password node while `when_offline != "drop"` or while `dedupe`/`ttl_s` is present; also reject a password `text_input` whose `on_submit` is non-`drop` even when it omits `capture_fields`. (2) Defence in depth in `CompanionEngine.dispatchAction`: when `extraFields` is non-null (the volatile-secret path) refuse the `queue`/`wake` branch outright — return the 1201 `content-invalid` diagnostic instead of calling `queue.admit` — so no code path can ever hand a volatile field value to the durable store.

## [P1] [unverified] §23.5 / §22.3 — Unbounded `pendingEditors` work queue: a peer in SYNCING can grow it without limit and then blow past `max_editor_sessions` at READY

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:649  
**SPEC line:** 3396  
**Auditor:** Audit SS22 (capability registry and load management: traffic classes, 

**SPEC quote:**
> Implementations MUST enforce Section 4 limits before allocating proportional resources. They MUST bound decoded images, base64 payloads, canvas operations, rich-text spans, table cells, chart points, trigger registrations, reminders, editor sessions, and outstanding dialogs.  [§22.3, SPEC.md:3309] Every endpoint MUST bound its inbound frame queue, parsed-message queue, outstanding request count, and module-specific work queues. It MUST apply transport backpressure before unbounded memory growth.

**Detail:** `reconcileEditors` (CompanionEngine.kt:638-656) is reached from `handleSurfaceUpdate` (:602) on every applied `surface.update`. `surface.update` is legal in SYNCING (MethodRegistry.kt:22, `SR`). When the accepted spec's synchronized editor keeps the same `editor_id` but changes `document`, line 646 calls `closeEditor(existed, editorId)` — which does `editors.remove(document to editorId) ?: return` (:1196) and therefore does NOT touch `pendingEditors` — and then line 649 APPENDS a new `Triple(document, editorId, seed)` because `state != READY`. `pendingEditors` is a plain `ArrayList` (:614) with no cap, no dedupe by `editor_id`, and no pruning of superseded entries; it is drained only on entering READY (:433-435) or on `close()` (:149). The `max_editor_sessions` gate at :585-590 counts only `surfaceEditors` (identities currently present in accepted documents) — 1 in this scenario — so it never fires. Each retained Triple holds the editor node's full `value` seed string, bounded only by `max_frame_bytes` (4 MiB). Worse, the READY drain at :435 loops `for ((doc, eid, seed) in pend) openEditor(doc, eid, seed)` with NO limit re-check, and `openEditor` (:1118-1130) unconditionally inserts into `editors` and emits one `edit.open` notification carrying the full `text` seed — so N stale identities become N live editor sessions and N frames, against an advertised `max_editor_sessions` of 8 (DeviceBridge.kt:74).

**Failure scenario:** An authenticated peer that has not yet sent `session.ready` (state SYNCING, which the peer alone controls) sends repeated `surface.update` for `app:x` with revisions 1,2,3,… each carrying spec `{t:"editor", id:"e1", document:"d<N>", value:<1 MiB string>}`. Every request passes the `max_editor_sessions` check (othersEditorCount 0 + newEditors.size 1 = 1 ≤ 8), applies, and appends one 1 MiB Triple to `pendingEditors`. 300 such requests retain ~300 MiB of Strings that nothing can free → Android heap OOM and process death (taking the durable stores' in-memory views with it). If the peer instead stops at, say, 500 entries and sends `session.ready`, the drain at :435 opens 500 editor sessions (limit 8) and emits 500 `edit.open` frames totalling ~500 MiB in a single `@Synchronized` block.

**Proposed fix:** Make `pendingEditors` a keyed latest-wins map rather than an append-only list: key on `(surface, editor_id)` (or at minimum `editor_id`) so a document change REPLACES the pending entry instead of adding one, and have `closeEditor`/`reconcileEditors` drop the pending entry for an identity that is no longer present. Additionally, count pending identities in the `max_editor_sessions` check at :587 (SPEC.md:296 says the limit covers identities "whose `edit.open` is pending until `READY`"), and re-apply the limit inside the READY drain at :435 so the drain can never open more sessions than the advertised bound.

## [P1] [unverified] §4.1 — Companion never rejects unpaired surrogate escapes; the value is preserved and later replaced with '?'

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/FrameCodec.kt`:126  
**SPEC line:** 121  
**Auditor:** Audit SS4.1 through SS4.4 (JSON data model: value types, object/duplic

**SPEC quote:**
> After JSON escape decoding, every string and member name MUST be a sequence of Unicode scalar values; an unpaired surrogate escape is invalid and MUST be rejected rather than preserved or replaced.

**Detail:** `FrameDecoder.parseBody` (FrameCodec.kt:126-154) enforces strict UTF-8 (CodingErrorAction.REPORT), the depth cap, single-object top level, and duplicate members — but nothing checks that decoded strings and member names are Unicode SCALAR values. §6.2 makes "Section 4.1's duplicate-member and encoding rejections ... REQUIRED for the Companion". I ran the pinned parser (org.json 20240303, companion/gradle/libs.versions.toml:6) against `{"a":"\ud800"}`: it parses successfully and the resulting java.lang.String retains the unpaired U+D800 — no exception anywhere. `grep -rn 'surrogate|isHighSurrogate|isSurrogate|wellFormed'` over companion/ returns no main-source hit, so no downstream guard exists either (EditorSession only does codePointCount arithmetic). The value then flows into SpecValidator (a String passes every `is String` test), into the SurfaceStore record and its durable backing, and back onto the wire; Java's String->UTF-8 conversion (`encodeFrame`, FrameCodec.kt:187, and the backing file write) substitutes '?' 0x3F for the unpaired surrogate. So the receiver both PRESERVES it in memory and REPLACES it on egress — the two outcomes the sentence names explicitly. The Emacs twin is correct: Emacs 30.1's json-parse-string signals `json-invalid-surrogate-error` (verified by execution), so the twins disagree on the same frame.

**Failure scenario:** Emacs pushes `surface.update` with spec `{"t":"text","text":"A\ud800B"}`. The Companion MUST reject the body. Instead it accepts, SurfaceStore persists the record, the renderer shows "A?B", and the value re-emitted on any echo path is "A?B" — so §14.6/§13.6 draft equality (`jsonValueEquals(authoredValue(node), value)`, SurfaceStore.kt:276) now compares a replaced string against the authored one and never matches, permanently marking a clean draft dirty. Reachable pre-authentication too: `session.hello` `client.name` takes the same path.

**Proposed fix:** In `parseBody`, after the UTF-8 decode and depth scan and before `JSONTokener`, run one linear scan of `text` rejecting any char in U+D800..U+DFFF that is not part of a well-formed high+low pair (`Character.isHighSurrogate(c) && i+1<n && Character.isLowSurrogate(text[i+1])`), throwing the taxonomy error the §4.1 amendment selects (see the companion SPEC finding on which error class applies). Scanning the raw text also catches the escaped form, since the escape has already been decoded by neither party at that point — so apply the same check to the parsed strings, or unescape-and-check, whichever the reference decoder mirrors in ebp.el.

## [P1] [unverified] §4.5 — max_rich_spans and max_table_cells are neither advertised in the welcome nor enforced anywhere, though rich_text and table are advertised node types

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/DeviceBridge.kt`:67  
**SPEC line:** None  
**Auditor:** Audit SS4.5 (limits and bounds) exhaustively. Enumerate EVERY limit na

**SPEC quote:**
> | `max_rich_spans`, `max_table_cells` | REQUIRED when `rich_text` or `table`, respectively, is advertised |  …  A receiver MUST enforce these limits before durable admission or expensive decoding.  …  Unless a row states otherwise, `max_canvas_ops`, `max_chart_points`, `max_rich_spans`, and `max_table_cells` are aggregate counts across one SurfaceSpec or dialog document.

**Detail:** NodeSupport advertises `rich_text` in APP_NODE_TYPES and DIALOG_NODE_TYPES (via CONTENT_NODE_TYPES, NodeSupport.kt:18-20) and `table` in APP_NODE_TYPES (via LAYOUT_NODE_TYPES, NodeSupport.kt:32-34), and DeviceBridge builds surface_profiles from those sets (DeviceBridge.kt:66). Both limits are therefore REQUIRED members of the welcome `limits` object. The limits JSONObject at DeviceBridge.kt:67-85 lists max_frame_bytes … max_chart_points/max_canvas_ops but contains neither max_rich_spans nor max_table_cells, and CompanionEngine.checkLimits (CompanionEngine.kt:1583-1651) never requires them. A repo-wide grep for max_rich_spans/max_table_cells/maxRichSpans/maxTableCells finds hits only in ebp/SPEC.md and ebp/contract.json — zero occurrences in any .kt or .el source. Correspondingly SpecValidator.validateSpans (SpecValidator.kt:604-613) only type-checks each span's `text`, and SpecValidator.validateTable (SpecValidator.kt:640-665) walks rows/cells with no count at all; SpecValidator.Ctx (line 70-83) carries no span or cell counter. Neither limit is bounded indirectly: spans and cells are not Nodes, so neither the 10,000-node nor the 10,000-children fixed limit applies to them. The only remaining bound is the 4 MiB body.

**Failure scenario:** Emacs sends surface.update for app:doc whose spec is a single {t:"rich_text", spans:[{"text":"a"}, …]} node with ~280,000 spans (14 bytes each, a ~3.9 MB body inside max_frame_bytes). SpecValidator accepts it (only per-span type checks run), SurfaceStore.update persists the whole spec to ebp-surfaces.json, and the renderer builds one AnnotatedString with 280,000 style ranges — the exact expensive-decode case §4.5 says MUST be bounded before durable admission. The same holds for a `table` with one row of ~200,000 cells. Emacs cannot self-limit either, because the welcome reports no max_rich_spans/max_table_cells to respect.

**Proposed fix:** Add `max_rich_spans` and `max_table_cells` to DeviceBridge's limits object with the values the renderer can sustain, require them in checkLimits whenever the corresponding node type appears in any advertised profile's node_types, and thread them through SpecValidator.Ctx as running document-wide counters (like nodeCount): increment in validateSpans by arr.length() and in validateTable by each row's cells.length(), throwing ContentInvalid("exceeds max_rich_spans"/"exceeds max_table_cells") when the running total passes the limit. Wire them from CompanionEngine (surface path via SurfaceStore's constructor, dialog path at CompanionEngine.kt:1414).

## [P1] [unverified] §4.5 / §10.2 / §14.1 — Input drafts are admitted with no max_field_bytes or max_input_state_bytes check, so retained input_state can grow past max_frame_bytes and permanently break the welcome

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SurfaceStore.kt`:249  
**SPEC line:** None  
**Auditor:** Audit SS4.5 (limits and bounds) exhaustively. Enumerate EVERY limit na

**SPEC quote:**
> Every `input_state` value MUST have the JSON type required by its node type and MUST fit `max_field_bytes`, and the complete object MUST fit `max_input_state_bytes` under Section 4.5's limit encoding. Before accepting a non-password user change that would enlarge retained input state beyond that aggregate limit, the Companion MUST refuse the change, preserve the preceding logical and native value, and show a local validation diagnostic.  … (§14.1) It MUST enforce `max_field_bytes` while accepting user input and MUST NOT create an occurrence whose captured field exceeds that limit; it SHOULD expose a local validation diagnostic instead.  … (§4.5) Queue admission up to `max_queued_events`, any supported negotiation result, and any permission-state change MUST remain inside the reservation.

**Detail:** There is no max_field_bytes or max_input_state_bytes enforcement anywhere on the surface input path. Chain: Renderer.kt:266 onValueChange (text_input) / Renderer.kt:345 (local editor) -> RenderCtx.state (Renderer.kt:93) -> DeviceBridge.state (DeviceBridge.kt:183) -> CompanionEngine.publishState (CompanionEngine.kt:348). publishState checks only isStatefulNode and isPasswordNode, then calls surfaces.putDraft at line 354. SurfaceStore.putDraft (SurfaceStore.kt:249-256) stores the value unconditionally and calls persist() (FileSurfaceBacking -> ebp-surfaces.json). SurfaceStore.inputState() (SurfaceStore.kt:236-245) then aggregates every draft with no cap, and buildWelcome inserts it verbatim (CompanionEngine.kt:1554). A repo-wide grep for max_field_bytes/MAX_FIELD_BYTES outside tests finds enforcement only in AppCapabilities.readClipboard (§20.3) and ContextlessEvents.routeNotificationAction (§18.5 inline reply, ContextlessEvents.kt:128); the surface draft path and dispatchAction's capture_fields loop (CompanionEngine.kt:273-285) have no per-field bound at all — only the whole-params max_event_bytes gate at line 294, which is 4x looser (262144 vs 65536) in the shipped config. checkLimits (CompanionEngine.kt:1583) assumes the aggregate holds: it reserves exactly limits.max_input_state_bytes of welcome headroom (line 1647), a reservation nothing enforces.

**Failure scenario:** Shipped config: max_field_bytes=65536, max_input_state_bytes=262144, max_frame_bytes=4194304 (DeviceBridge.kt:67-85). Emacs pushes six app:* surfaces, each with an `editor` node {publish_state:true, no document} seeded with a ~700 KB org file. The user types one character in each: publishState -> putDraft retains six ~700 KB drafts (each already 10x over max_field_bytes) and persists them to ebp-surfaces.json. On the next reconnect buildWelcome puts the ~4.2 MB input_state into the welcome; respondResult -> emit -> encodeFrame (FrameCodec.kt:188) throws FrameClose because the body exceeds 4,194,304; that exception is caught by the dispatch guard in feed() (CompanionEngine.kt:100-104) and the session is closed with no welcome. Because the drafts are durable, every subsequent reconnect repeats: the pairing can never authenticate again. Short of the brick, a single edited 200 KB field is captured verbatim into event.action.fields (params ~200 KB < max_event_bytes) and delivered/queued, which §14.1 forbids outright.

**Proposed fix:** Bound the draft at admission, not at report time. In CompanionEngine.publishState (before surfaces.putDraft), compute the JCS-encoded UTF-8 size of `value`; if it exceeds limits.max_field_bytes, refuse the change, leave the prior draft intact, and invoke a local-diagnostic listener (the dialogOverflowListener pattern at CompanionEngine.kt:1395). Add a SurfaceStore method that returns the current aggregate encoded size of `drafts` and refuse a change whose delta would push the total past limits.max_input_state_bytes (a size-reducing change stays legal). Additionally, in dispatchAction's capture_fields loop (CompanionEngine.kt:274-280) reject the occurrence with 1201 field-too-large when any captured value exceeds max_field_bytes, mirroring routeNotificationAction.

## [P1] [unverified] §4.5 / §23.5 — `max_table_cells` (and `max_rich_spans`) are neither advertised in the welcome nor enforced, so a table's cell count is completely unbounded

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/DeviceBridge.kt`:85  
**SPEC line:** None  
**Auditor:** Audit SS17.4 through SS17.6 (layout nodes, the scaffold and its slots,

**SPEC quote:**
> | `max_rich_spans`, `max_table_cells` | REQUIRED when `rich_text` or `table`, respectively, is advertised | … Implementations MUST enforce Section 4 limits before allocating proportional resources. They MUST bound decoded images, base64 payloads, canvas operations, rich-text spans, table cells, chart points, trigger registrations, reminders, editor sessions, and outstanding dialogs.

**Detail:** `table` is advertised in the app profile (NodeSupport.kt:34,41-44) and `rich_text` in both the app and dialog profiles (NodeSupport.kt:19), so §4.5 makes `max_table_cells` and `max_rich_spans` REQUIRED members of the authenticated welcome's `limits`. The limits object (DeviceBridge.kt:68-85) advertises max_image_*/max_chart_points/max_canvas_ops but neither of these two; `grep -r max_table_cells\|max_rich_spans companion/` returns nothing outside contract.json. SpecValidator.Ctx carries only maxCaptureFields/maxChartPoints/maxCanvasOps (SpecValidator.kt:70-77) and `validateTable` (SpecValidator.kt:640-665) counts nothing. The other bounds do not cover cells: `walkNode` increments `ctx.nodeCount` only for objects carrying a `t` discriminator (SpecValidator.kt:343), and table rows/cells/spans have no `t` — they are walked by `walkValue`, which never counts. `max_children_per_node` applies only to a member literally named `children` (SpecValidator.kt:368-374), not to `rows`/`cells`/`spans`. The sole remaining bound is `max_frame_bytes` (4 MiB). The renderer then measures every cell eagerly in one custom `Layout` with no virtualisation (TableGrid, LayoutNodes.kt:523-579).

**Failure scenario:** Emacs (or a version-skewed/nonconforming sender) pushes one `surface.update` just under 4 MiB whose single `table` node carries ~150,000 cells of the form `{"spans":[{"text":"a"}]}`. Validation reports 1 node and admits it; the surface is persisted and rendered, TableGrid measures 150,000 Text composables in a single measure pass, and the Companion ANRs/OOMs. Separately, Emacs has no way to learn the cell budget because the welcome never reports one, so a conformant sender cannot respect a limit §4.5 says MUST be reported.

**Proposed fix:** Advertise `max_table_cells` and `max_rich_spans` in DeviceBridge's limits object; add `maxTableCells`/`maxRichSpans` to `SpecValidator.Ctx` (threaded from `config.limits` exactly as maxChartPoints/maxCanvasOps are at CompanionEngine.kt:43-44/1416-1417 and SurfaceStore.kt:20-21), accumulate cells in `validateTable` and spans in `validateSpans` across the whole document, and reject with 1201 when either aggregate is exceeded.

## [P1] [unverified] §5.2 — DeviceBridge terminates the authenticated session on TCP accept, not on successful authentication — any local process can DoS the Emacs session

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/DeviceBridge.kt`:129  
**SPEC line:** 337  
**Auditor:** Audit SS5 (transport profiles) and SS6 (Content-Length framing) agains

**SPEC quote:**
> The `android-loopback-tcp` core profile permits exactly one paired Emacs authority and one authenticated authoritative session at a time. Creating a new pairing MUST first revoke the old pairing under Section 9.1. When a new session authenticates successfully, the Companion MUST terminate the older session before the new session enters `SYNCING`.

**Detail:** §5.2 conditions supersession on the newcomer *authenticating successfully*. DeviceBridge.start()'s accept loop does it on `accept()`: `val socket = server.accept(); current?.runCatching { close() }; current = socket` (DeviceBridge.kt:127-130). The close happens before a single byte is read, before `session.hello`, before `auth.response`, and before the new CompanionEngine even exists. Grepping the whole tree for supersession logic (`supersede|newest|older session`) finds nothing else: CompanionEngine has no session registry and never terminates a peer engine on `AUTH_VERIFIED`, so accept-time close is the only mechanism. The blast radius on the old session is real, not cosmetic: closing the socket unwinds serve()'s read loop into `engine.close("transport closed")`, which clears the durable queue's in-flight marker (CompanionEngine.kt:129), dismisses every outstanding dialog (CompanionEngine.kt:133-137), and dismisses all pie menus. Compounding it, `CompanionEngine.init` calls `firing.attach(this)` and serve() calls `CompanionStores.setLiveSession(engine)` (DeviceBridge.kt:249) for the unauthenticated newcomer, so the newcomer also takes over the newest-wins trigger-drop slot pre-auth. §23.6 makes the intent explicit — "Loopback addressing prevents remote network access but does not authenticate a local process. The HMAC handshake supplies that authentication" — which is exactly why §5.2 gates supersession on authentication rather than on connection.

**Failure scenario:** Emacs is READY with an open dialog and an `event.action` in flight. An unrelated unprivileged local process (an app scanning loopback, or `nc 127.0.0.1 8765`) opens a TCP connection and sends nothing. `server.accept()` returns, `current?.close()` tears down the authenticated socket, the dialog is dismissed locally, the in-flight queue record is released, and the paired Emacs endpoint loses its session — while the attacker never presents a pairing_id or an HMAC proof. Repeating the connect in a loop keeps the paired session permanently unusable.

**Proposed fix:** Do not close `current` in the accept loop. Track the live authenticated engine and have the newcomer's engine terminate it from the auth path: in CompanionEngine, at the point where `SessionEvent.AUTH_VERIFIED` is applied (immediately before the welcome/`SYNCING` transition), call a host-supplied `onAuthenticated` hook that closes the previously authenticated socket/engine, then set `current = socket`. Also defer `firing.attach(this)` and `CompanionStores.setLiveSession(engine)` from construction/serve() to that same post-authentication point so an unauthenticated socket never displaces the live-session slot.

## [P1] [unverified] §5.2 / §23.6 — DeviceBridge terminates the live authenticated session at `accept()` — before authentication — so any unauthenticated local process can kill and hijack the EBP session

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/DeviceBridge.kt`:129  
**SPEC line:** 337  
**Auditor:** Audit SS22 (capability registry and load management: traffic classes, 

**SPEC quote:**
> When a new session authenticates successfully, the Companion MUST terminate the older session before the new session enters `SYNCING`.  [§23.6, SPEC.md:3403] Loopback addressing prevents remote network access but does not authenticate a local process. The HMAC handshake supplies that authentication.

**Detail:** The accept loop closes the previous socket the instant a new TCP connection arrives: `val socket = server.accept()` (:127) then `current?.runCatching { close() }` (:129) — with no handshake, no `session.hello`, and no proof verification in between. §5.2 conditions supersession on "a new session authenticates successfully", and §10.1 (SPEC.md:752) likewise lists "explicit replacement by a newer AUTHENTICATED session" as the transition. Two further pre-authentication effects compound it: `serve()` publishes the brand-new engine into the process-wide live-session slot at :251 (`CompanionStores.setLiveSession(engine)`) before any handshake, and `CompanionEngine`'s constructor calls `firing.attach(this)` at CompanionEngine.kt:87 — an `AtomicReference.set`, newest-wins — so the unauthenticated connection also displaces the real session as the `LiveSession` used by `TriggerFiringService` (:191) and by cold reminder/notification tap receivers for `drop` delivery. `deliverLiveDrop` does gate on `state != READY` (CompanionEngine.kt:839), so no data leaks to the attacker, but every live `drop` occurrence is silently lost instead of reaching the real Emacs. Finally, ebp.el/the Companion implement no handshake timeout (§10.1 makes it MAY), so a single connection that never sends `session.hello` holds the slot indefinitely.

**Failure scenario:** Any other app on the device (Android grants `INTERNET` near-universally, and no permission is needed to dial 127.0.0.1) runs `while(true){ Socket("127.0.0.1",8765) }` — or opens one socket and never speaks. Each `accept()` closes the authenticated Emacs connection at :129 and steals both the `CompanionStores` live-session slot and the `TriggerFiringService` attachment. Emacs's `event.action` requests die mid-flight, every surface, dialog, pie menu and editor session is torn down (`close()` at :325), reconnection is immediately killed again, and live `drop` trigger/reminder-tap deliveries are routed to the attacker's never-READY engine and dropped. A permanent, zero-privilege denial of the entire EBP session and of §21 live trigger delivery, achieved without ever touching the HMAC handshake that §23.6 identifies as the sole authenticator of a local process.

**Proposed fix:** Move supersession behind authentication. In `serve()`, keep the newly accepted socket in a `provisional` slot; only when the engine reaches SYNCING (i.e. `handleAuth` succeeded) close the prior socket, publish `CompanionStores.setLiveSession(engine)`, and call `firing.attach(this)` — move that call out of `CompanionEngine.init` into the AUTH_VERIFIED transition (CompanionEngine.kt:1528). Bound the number of simultaneously accepted-but-unauthenticated sockets (1 is sufficient: refuse or immediately close a second) and add the §10.1-RECOMMENDED 30-second handshake deadline so an idle pre-auth connection cannot hold the slot.

## [P1] [unverified] §5.2 / §9 — An unauthenticated loopback connection evicts the authenticated session and captures the device-lifetime live-delivery slot

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/DeviceBridge.kt`:129  
**SPEC line:** 336  
**Auditor:** Audit SS9 (pairing and mutual authentication) against companion/wire/A

**SPEC quote:**
> When a new session authenticates successfully, the Companion MUST terminate the older session before the new session enters `SYNCING`.

**Detail:** Supersession is keyed on TCP accept, not on successful authentication. `DeviceBridge.start()` does `val socket = server.accept()` (line 127) then immediately `current?.runCatching { close() }` (line 129) — the previously authenticated Emacs socket is torn down before the newcomer has sent even `session.hello`. `serve()` then constructs the engine (line 237) whose `init` runs `firing.attach(this)` (companion/wire/.../CompanionEngine.kt:87) and calls `CompanionStores.setLiveSession(engine)` (DeviceBridge.kt:251) — again before any proof is verified. So a peer that never authenticates becomes both the `TriggerFiringService` live session and the `CompanionStores` live slot. The displaced engine's `close()` runs `firing.detach(oldEngine)` / `clearLiveSession(oldEngine)`, but those are compare-and-set against the slot the newcomer already owns, so they are no-ops: the unauthenticated engine keeps both slots. Nothing in the wire layer gates attachment on `SessionEvent.AUTH_VERIFIED`; `handleAuth` (CompanionEngine.kt:1507) is the only place authentication is established and it touches neither slot.

**Failure scenario:** Emacs is paired and READY. Any other local process (an app with INTERNET permission, or `adb shell nc`) opens a socket to 127.0.0.1:8765 and then sleeps, sending nothing. (1) Emacs's authenticated session is closed instantly by DeviceBridge.kt:129 even though the newcomer never authenticates — a token-free permanent DoS if the connect is looped. (2) A `drop`-policy device trigger fires 5 s later; TriggerFiringService routes it through `LiveSession.deliverLiveDrop`, which is now the attacker's engine in state CONNECTED, so `if (state != SessionState.READY) return` (CompanionEngine.kt:839) discards it — a `drop` event is never queued, so the user's trigger event is permanently lost, and it would have been delivered had the unauthenticated socket not existed.

**Proposed fix:** Do not let an unauthenticated connection displace anything. In `DeviceBridge.serve()`, defer both `CompanionStores.setLiveSession(engine)` and the closing of the prior socket until the engine reports AUTH_VERIFIED (add an engine `authenticatedListener`, or have the engine invoke a host callback at the `state = sessionStep(state, SessionEvent.AUTH_VERIFIED)` line, CompanionEngine.kt:1529). Move `firing.attach(this)` out of `CompanionEngine.init` (line 87) to that same point. Keep the pre-auth socket accepted but non-authoritative, and bound the number of concurrent unauthenticated sockets.

## [P1] [unverified] §6.2 (with §4.1) — ebp.el reference decoder accepts non-empty top-level arrays, including JSON-RPC batches

**Location:** `emacs/ebp.el`:228  
**SPEC line:** 447  
**Auditor:** Audit SS4.1 through SS4.4 (JSON data model: value types, object/duplic

**SPEC quote:**
> One frame contains exactly one JSON-RPC Message object. Top-level arrays are prohibited, including JSON-RPC batches. After reading a complete body: ... a top-level array or non-object JSON value MUST produce one Invalid Request response with `id: null`

**Detail:** `ebp--parse-body` (ebp.el:218-239) tests the top-level value with `(unless (and (listp value) (or (null value) (consp (car value)))) ...)`. `json-parse-string` is called with `:object-type 'alist :array-type 'list`, so BOTH objects and arrays come back as Lisp lists. The guard therefore passes for any array whose first element is itself a container: `[{...}]` decodes to `(((jsonrpc . "2.0") ...))`, whose `car` is a cons, so the `ebp-invalid-request` signal is never raised. The explicit batch check on the next lines (232-236) only fires `(when (and (null value) ...)`, i.e. only for the empty array `[]`, which is the sole array shape the fixture corpus exercises. I ran the decoder to confirm: `[]` -> ebp-invalid-request, `[1,2]` -> ebp-invalid-request, but `[[1]]`, `[{"jsonrpc":"2.0","method":"a"}]` and a two-element batch all return OK with a bogus "message object". The Kotlin twin is correct here (FrameCodec.kt:150 `if (value !is JSONObject) throw InvalidRequest`), so the twins diverge on the exact shape §6.2 names. §6.2 scopes these receiver duties as RECOMMENDED for the live Emacs endpoint, but this function is the exported §6 reference decoder used by conformance suites and by any future non-jsonrpc transport, and it already claims the rule in its own docstring and error taxonomy (`ebp-invalid-request` = "top-level non-object, batch array", ebp.el:72-73) — a reference decoder that accepts the prohibited shape will certify non-conformant peers.

**Failure scenario:** Feed the decoder one frame whose body is the JSON-RPC batch `[{"jsonrpc":"2.0","method":"a"},{"jsonrpc":"2.0","method":"b"}]` (Content-Length 63). Verified by execution: `ebp-decoder-feed` returns a single "message" `((((jsonrpc . "2.0") (method . "a")) ((jsonrpc . "2.0") (method . "b"))))` instead of signalling `ebp-invalid-request`, so no Invalid Request response with `id: null` is ever produced and the prohibited batch is handed to the dispatcher layer.

**Proposed fix:** Decide array-vs-object from the JSON text, not from the Lisp shape. Before the `listp` test, take the first non-whitespace character of TEXT and signal `ebp-invalid-request` for `[` unconditionally (covering `[]`, `[1,2]`, `[[1]]`, and every batch), then keep the existing scalar rejection for the remaining cases. Alternatively parse with `:array-type 'array`, which makes arrays vectors and lets `(listp value)` alone discriminate; the `(null value)` special case can then be dropped.

## [P1] [unverified] §7.3 — ebp.el's inbound dispatchers ignore the §11 registry: no sender/class check, so a wrong-class request runs its handler and replies `result: null`, and a wrong-direction request gets -32601 instead of -32600

**Location:** `emacs/ebp.el`:776  
**SPEC line:** None  
**Auditor:** Audit SS11 (method registry) and SS12 (versioning and compatibility). 

**SPEC quote:**
> A receiver MUST verify the method's sender, class, allowed session state, and
parameters before invoking a handler.

- An unknown request MUST receive `-32601 Method not found`.
- An unknown notification MUST be logged and ignored.
- A request sent by the wrong endpoint or in the wrong class MUST receive
  `-32600 Invalid Request`.
- A notification sent by the wrong endpoint or in the wrong class MUST be
  logged and ignored.

**Detail:** The Companion side implements the §11 registry properly (CompanionEngine.kt:397-402 resolves METHOD_REGISTRY and answers -32600 for `spec.sender == Sender.COMPANION || !spec.isRequest`; CompanionEngine.kt:696-698 mirrors it for notifications). The Emacs side has no registry at all. `ebp-client--request-dispatcher` (emacs/ebp.el:764-780) and `ebp-client--notification-dispatcher` (emacs/ebp.el:782-793) both key off ONE flat hash table, `ebp-client-handlers`, populated at emacs/ebp.el:542-557 with event.action, state.changed, edit.open, edit.delta, edit.caret, edit.close, edit.complete. Nothing in that table records whether an entry is a request or a notification, or which endpoint may send it, and `-32600` appears nowhere in ebp.el (only the unrelated `ebp-invalid-request` decoder condition at :73/:230/:236). Three distinct §7.3 MUSTs are consequently unmet:

(a) Wrong CLASS, request form. A notification-class method arriving with an `id` finds its handler at emacs/ebp.el:776 and is invoked. jsonrpc.el (jsonrpc.el:298-317, Emacs 30.1) wraps the request-dispatcher's return value as ``(:result ,(funcall rdispatcher ...))`` and replies with it.

(b) Wrong CLASS, notification form. A request-class method arriving with no `id` finds its handler at emacs/ebp.el:790-791 and is invoked as a notification — jsonrpc.el:319-320 calls ndispatcher with no reply path.

(c) Wrong DIRECTION. An Emacs-sender method (`surface.update`, `dialog.show`, `queue.replay`, `triggers.set`, …) arriving as an inbound request is not in the handler table, so emacs/ebp.el:779-780 answers `-32601 Method not found`. §7.3 reserves -32601 for UNKNOWN methods and requires -32600 for a known method in the wrong direction; §12 rule 4 (SPEC.md:976) repeats "Unknown request methods receive `-32601`". A registered EBP 2 method is not unknown.

§24.6 item 4 (SPEC.md:3519) names "wrong-direction, wrong-class, unknown-request, and unknown-notification dispatch" as a REQUIRED adversarial test; test/ebp-wire-test.el covers only the unknown-request case (`ebp-test-client-answers-unknown-request`, :451) and the pre-auth case (:593), so all three branches above are untested on the Emacs side.

**Failure scenario:** (a) The Companion sends `{"jsonrpc":"2.0","id":7,"method":"state.changed","params":{"surface":"app:main","revision_seen":41,"id":"title","value":"x"}}`. ebp.el runs `ebp-client--handle-state-changed` (emacs/ebp.el:941-955) — it writes `input-values` and fires every `state-changed-functions` hook — then returns nil (the value of the enclosing `when`/`dolist`). jsonrpc.el replies `{"jsonrpc":"2.0","id":7,"result":null}`. Required: `-32600 Invalid Request` with no handler invocation. The reply also violates §7.1 (SPEC.md:477-478) "`null` MUST NOT be used as a generic success result."
(b) The Companion sends `{"jsonrpc":"2.0","method":"event.action","params":{"event_id":"00112233445566778899aabbccddeeff","action":"demo.tap","occurred_at_ms":1784700000000}}` with no `id`. ebp.el runs `ebp-client--handle-event-action`, which dispatches the allowlisted semantic action AND durably commits the EventId receipt (`ebp-client--receipt-commit`, emacs/ebp.el:908) — a committed side effect and a permanently-burned event_id — with no response frame, because a notification has none. Required: logged and ignored. If the same wrong-class notification is malformed, `ebp-client--error` (:470-475) calls `jsonrpc-error`, which signals `jsonrpc-error` inside jsonrpc.el's notification branch (jsonrpc.el:319-320) — a branch with no `condition-case` — so the signal escapes `jsonrpc-connection-receive` into the process filter.
(c) The Companion sends `{"jsonrpc":"2.0","id":8,"method":"surface.update","params":{}}`. ebp.el answers `-32601`; §7.3 requires `-32600`.

**Proposed fix:** Port MethodRegistry.kt's table into ebp.el as a defconst alist (method -> (sender class states)) and consult it FIRST in both dispatchers, before the handler lookup: in `ebp-client--request-dispatcher`, after the 1200 pre-auth gate, look the method up — absent => -32601; present with sender `companion` absent or class `notification` => `-32600 Invalid Request` / kind `invalid-request`; present but `state` not in its legal set => 1204. In `ebp-client--notification-dispatcher`, apply the same lookup and silently drop (with a `message`) on unknown, wrong-sender, wrong-class, or wrong-state instead of dispatching. Keep `ebp-client-handlers` as the handler map only. Add ERT cases for (a) state.changed-as-request => -32600, (b) event.action-as-notification => ignored and no receipt committed, (c) surface.update inbound => -32600, closing §24.6 item 4.

## [P1] [unverified] §7.3 — Inbound dispatch has no sender/class check: notification-class methods execute as requests (answered `result: null`) and request-class methods execute as notifications, running allowlisted semantic actions

**Location:** `emacs/ebp.el`:776  
**SPEC line:** None  
**Auditor:** Audit emacs/ebp.el as a whole against every SPEC duty assigned to "a c

**SPEC quote:**
> - A request sent by the wrong endpoint or in the wrong class MUST receive
  `-32600 Invalid Request`.
- A notification sent by the wrong endpoint or in the wrong class MUST be
  logged and ignored.

**Detail:** `ebp-client-register-handler` (ebp.el:561-566) writes every inbound method — request-class (`event.action`, `edit.complete`) and notification-class (`state.changed`, `edit.open`, `edit.delta`, `edit.caret`, `edit.close`) — into ONE `handlers` hash table (struct slot, ebp.el:495). `ebp-client--request-dispatcher` (ebp.el:776-780) looks a method up in that table with no class or sender check, and `ebp-client--notification-dispatcher` (ebp.el:790-792) does the same. There is no consultation of the §11 registry's Sender/Class columns anywhere in the file. Three distinct MUST failures follow: (a) a notification-class method arriving WITH an `id` is executed and its nil return becomes a JSON-RPC success — jsonrpc.el wraps the dispatcher value as `` `(:result ,...) `` (jsonrpc.el:307-309) and serializes nil with `:null-object nil` (jsonrpc.el:646-648), so the wire carries `"result":null`, which §7.1 line 476 separately forbids; (b) an Emacs-sender method arriving as a request (`queue.replay`, `surface.update`, `dialog.show`) finds no handler and falls to `ebp-client--error ... -32601` (ebp.el:779) instead of -32600; (c) a request-class method arriving WITHOUT an `id` is dispatched by the notification dispatcher, so `ebp-client--handle-event-action` runs the full §14.4 server — it invokes the application's allowlisted action handler and durably commits the EventId receipt (ebp.el:905-909) — for a frame that can never be answered.

**Failure scenario:** Companion (buggy or hostile) sends `{"jsonrpc":"2.0","id":9,"method":"edit.open","params":{"document":"doc:x","editor_id":"body","session":"00…ff","seq":0,"text":"pwned","cursor":0}}` while READY. `ebp-client--request-dispatcher` finds `ebp-client--handle-edit-open`, which `puthash`es a new mirror entry (ebp.el:978-983) and fires `edit-change-functions`, then returns nil. Emacs replies `{"jsonrpc":"2.0","id":9,"result":null}`. Required: `-32600 Invalid Request` with `data.kind:"invalid-request"` and NO mutation of the editor mirror. Separately, sending `{"jsonrpc":"2.0","method":"event.action","params":{"event_id":"00112233445566778899aabbccddeeff","action":"heading.todo-set","args":{"state":"DONE"},"occurred_at_ms":1784700000000}}` with no `id` executes the registered `heading.todo-set` handler and writes a durable receipt, with no response frame ever produced — a semantic action fired from a frame the SPEC says must be logged and ignored.

**Proposed fix:** Split the registry into request handlers and notification handlers (or attach a `:class` and `:sender` to each registration, projected from `contract.json`'s method table). In `ebp-client--request-dispatcher`: if the method is known but its registry class is `notification`, or its registry sender is `Emacs`, signal `ebp-client--error client -32600 "Invalid Request" "invalid-request"` before any handler runs; only truly unregistered methods get -32601. In `ebp-client--notification-dispatcher`: if the method's registry class is `request` or its sender is `Emacs`, log and return without calling the handler. Also make every request handler return an explicit object (never nil) so no `result: null` can escape.

## [P1] [unverified] §7.3 (with §7.1) — Emacs endpoint never verifies method class or direction before dispatch; a notification-class method sent as a request runs the handler and replies `result: null`

**Location:** `emacs/ebp.el`:776  
**SPEC line:** 503  
**Auditor:** Audit SS7 (JSON-RPC 2.0 conventions) and SS8 (error model) in both twi

**SPEC quote:**
> A receiver MUST verify the method's sender, class, allowed session state, and parameters before invoking a handler.

- An unknown request MUST receive `-32601 Method not found`.
- An unknown notification MUST be logged and ignored.
- A request sent by the wrong endpoint or in the wrong class MUST receive
  `-32600 Invalid Request`.
- A notification sent by the wrong endpoint or in the wrong class MUST be
  logged and ignored.

**Detail:** ebp.el keeps ONE handler table with no class or sender tag: `ebp-client-register-handler` (ebp.el:561-566) puts every inbound method — requests (`event.action`, `edit.complete`) and notifications (`state.changed`, `edit.open`, `edit.delta`, `edit.caret`, `edit.close`) — into `(ebp-client-handlers client)`. `ebp-client--request-dispatcher` (ebp.el:764-780) then does `(gethash (symbol-name method) (ebp-client-handlers client))` and funcalls whatever it finds, and `ebp-client--notification-dispatcher` (ebp.el:782-793) does the same. Neither consults a §11 registry, so neither of the two §7.3 wrong-class bullets is implemented on the Emacs side. Three consequences: (1) a Companion-sent NOTIFICATION-class method arriving as a REQUEST is executed and answered — the handler's return value becomes the JSON-RPC result, and every notification handler returns nil (`ebp-client--handle-edit-close` ends in `ebp-client--editor-changed` -> `dolist` -> nil; `ebp-client--handle-state-changed` returns nil or, on the reset branch, the string from `message`), so jsonrpc.el builds `(:result nil)` and `json-serialize ... :null-object nil` emits `"result":null` (verified in Emacs 30.1 batch), which §7.1 lines 476-477 forbid: "A successful operation with no return data MUST use `result: {}`. `null` MUST NOT be used as a generic success result."; (2) a REQUEST-class method arriving as a NOTIFICATION is executed with no possible reply — `event.action` as a notification runs the allowlisted action AND durably commits the EventId receipt (ebp.el:905-914), so the intent is consumed with no acknowledgement and a later legitimate delivery of that event_id answers "duplicate"; (3) a wrong-DIRECTION request (an Emacs-sender method such as `surface.update` arriving inbound as a request) falls through to `ebp-client--error ... -32601` at ebp.el:779, where §7.3 requires -32600. The Kotlin twin does exactly the required check — CompanionEngine.kt:397-401 looks the method up in METHOD_REGISTRY and answers -32601 for unknown, then -32600 for `spec.sender == Sender.COMPANION || !spec.isRequest` — so the two reference twins are asymmetric on a MUST that §24.6 item 4 ("wrong-direction, wrong-class, unknown-request, and unknown-notification dispatch") requires a core suite to exercise. Amendment #34 scoped down only §6.2/§4.1 receiver strictness (framing/decoding) for Emacs; §7.3 dispatch is untouched and §24.2 requires "the corresponding JSON-RPC ... rules". No ERT test covers it: test/ebp-wire-test.el:593 only checks pre-auth refusal and :451 only the unknown-method -32601.

**Failure scenario:** Post-auth (state `ready`), the Companion sends `{"jsonrpc":"2.0","id":42,"method":"edit.close","params":{"document":"d","editor_id":"e"}}` — `edit.close` is a Companion notification per §11. ebp.el's request dispatcher finds the registered handler, removes the mirrored editor session (a side effect from a wrong-class message), and jsonrpc.el replies on the wire with `{"jsonrpc":"2.0","id":42,"result":null}` instead of the required `-32600 Invalid Request`. Symmetrically, `{"jsonrpc":"2.0","method":"event.action","params":{"event_id":"00112233445566778899aabbccddeeff","action":"demo.tap","occurred_at_ms":1784700000000}}` (no id) runs the allowlisted `demo.tap` handler and commits its durable receipt, with no reply and no way for the Companion to learn the outcome.

**Proposed fix:** Give ebp.el the §11 registry it lacks: extend `ebp-client-register-handler` to take a class (`request`/`notification`) and permitted sender, or add a defconst method table mirroring companion/wire/.../MethodRegistry.kt. In `ebp-client--request-dispatcher`, before the handler lookup, answer `-32600 invalid-request` when the method is registered as a notification or as an Emacs-sender method, keeping -32601 only for genuinely unknown methods. In `ebp-client--notification-dispatcher`, log-and-ignore any method registered as a request or as an Emacs-sender method instead of funcalling it. Additionally coerce a nil/non-plist handler return into `ebp--empty-object` so `result: null` can never reach the wire, and add ERT coverage for both wrong-class directions.

## [P2] [unverified] SS14.4 — Transport loss never concludes an outstanding live event.action: no local diagnostic for a lost drop event and no password erasure trigger

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:122  
**SPEC line:** 1419  
**Auditor:** Audit SS14.4 through SS14.6 (the event.action request protocol, EventI

**SPEC quote:**
> A `drop` event MUST NOT be promoted to durable storage: it MAY be retried only while the same authenticated `READY` session remains usable and otherwise MUST be discarded with a local diagnostic. An event containing a password MUST NOT take even that in-session retry path: any result, error, cancellation, timeout, or transport loss concludes the attempt and requires immediate local erasure.

**Detail:** Companion-originated requests are correlated through `private val pending = HashMap<Int, (JSONObject?, JSONObject?) -> Unit>()` (CompanionEngine.kt:182); a drop event registers its callback in sendRequest (CompanionEngine.kt:189) and the entry is removed only when a matching response arrives (CompanionEngine.kt:168). close(reason) (CompanionEngine.kt:122-152) clears the queue in-flight marker, dialogs, pie menus and editor sessions, but never touches `pending`: the callbacks are simply abandoned with the engine object. Consequently DeviceBridge.action's error branch (DeviceBridge.kt:150-158), which is the only local-diagnostic path (onQueueProblem -> Toast), never runs for an event lost to transport failure, and for a password submission nothing signals 'the attempt concluded', so no erasure of the captured secret is ever initiated.

**Failure scenario:** The user taps a drop-policy button ('Mark DONE') on app:agenda. The Companion writes the event.action frame; the laptop lid closes and the socket dies before the result. DeviceBridge's serve() finally block calls engine.close("transport closed"), the pending callback is dropped on the floor, and the user sees no toast and no other indication — the item silently never gets marked, contrary to 'otherwise MUST be discarded with a local diagnostic'. In the password variant (an auth.login drop submit), the same silence means the volatile secret copy in the RenderTextInput state and in the abandoned params JSONObject is never erased even though transport loss is explicitly listed as concluding the attempt.

**Proposed fix:** In close(), drain `pending` under the monitor and invoke every callback with a synthetic transport-loss error ({code:-32603, data.kind:"internal-error", reason:"transport-lost"}) before clearing the map, so DeviceBridge surfaces the diagnostic. Add a per-request 'secret-bearing' flag set when extraFields/password capture is present, and on conclusion (result, error, or the close() drain) call an erasure hook that clears the renderer's password state and overwrites the captured fields entry.

## [P2] [unverified] SS14.6 — The 30-second password submission deadline (and its mandatory transport close) is not implemented anywhere

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:332  
**SPEC line:** 1530  
**Auditor:** Audit SS14.4 through SS14.6 (the event.action request protocol, EventI

**SPEC quote:**
> A password-bearing submission has a hard 30-second monotonic deadline beginning when the user commits it. Within that deadline, its `event.action` MUST receive a result or its dialog response MUST be completely handed to the transport. On expiry, the Companion MUST close the transport, abandon the attempt, and MUST NOT retry it.

**Detail:** There is no timer, deadline, or monotonic clock associated with any event.action anywhere in the Companion: a repository-wide grep for 30_000 / 30000 / deadline in companion/ finds only ImageLoader's 15s HTTP deadline. The password drop path is CompanionEngine.kt:330-335, which calls sendRequest and waits indefinitely for a response; there is no scheduled expiry, and close() is only ever called on transport error, dispatch failure, an unknown replay status (CompanionEngine.kt:535), or session replacement. The dialog side is the same: completeDialogSubmit (CompanionEngine.kt:1436-1456) writes the response with no deadline bookkeeping.

**Failure scenario:** Emacs pushes a password text_input with a drop on_submit. The user submits; Emacs's handler blocks (a hung TRAMP/authinfo lookup, a stopped process, or a wedged jsonrpc dispatch) and never returns a result. The Companion holds the request open forever: the frame containing the secret has been fully written to a stream whose remote outcome is indeterminate, the transport is never closed, the attempt is never abandoned, and the plaintext stays live in the pending correlation state and in the widget indefinitely — exactly the residency window the 30-second rule exists to bound.

**Proposed fix:** Mark secret-bearing submissions at dispatch (dispatchAction with extraFields, or a capture that resolves to a password node, and completeDialogSubmit with a password field). Record System.nanoTime() at commit and arm a 30s monotonic timer; on expiry call close("password deadline") — never emit an rpc.cancel frame, per 'the Companion MUST NOT append a cancellation frame to a stream that may end in a partial frame' — drop the pending callback, and run the erasure hook over the widget state, captured fields, and encoded buffers.

## [P2] [unverified] §10.1 — No `1204 session-state` gate: READY-only methods are dispatched normally during SYNCING, so a `state.changed` sent before `session.ready` is adopted into input state

**Location:** `emacs/ebp.el`:762  
**SPEC line:** None  
**Auditor:** Audit emacs/ebp.el as a whole against every SPEC duty assigned to "a c

**SPEC quote:**
> After authentication, a method illegal in the current state MUST receive
`1204 session-state` when it is a request and MUST be logged and dropped when it is a
notification.

**Detail:** `ebp-client--authenticated-p` (ebp.el:755-762) collapses `syncing` and `ready` into one "authenticated" bucket, and both dispatchers (ebp.el:764-793) branch only on that boolean. The string 1204 appears nowhere in emacs/ebp.el. But §11's registry assigns per-method legal states: `state.changed`, `edit.open`, `edit.delta`, `edit.caret`, `edit.close`, and `edit.complete` are all `R` only, while `event.action` is `S, R`. Including `syncing` is correct for `event.action` (replay delivers it pre-`session.ready`) but wrong for the R-only set. §10.3 reinforces this: the Companion may flush `state.changed` only after `session.ready` succeeds ("The Companion MUST then clear the surface-disconnection staleness timer and MUST immediately flush as ordered `state.changed` notifications…"). The existing test `ebp-test-inbound-fails-closed-before-auth` (test/ebp-wire-test.el:629-637) explicitly asserts the non-conforming behavior — it drives `state.changed` through the notification dispatcher in state `syncing` and requires the handler to have run.

**Failure scenario:** After the welcome is verified, Emacs is in `syncing` and, per §10.3 step 3, runs `:before-replay-function` to push surfaces (ebp.el:684-686) before `queue.replay`. In that window the Companion sends `state.changed {"surface":"app:main","revision_seen":0,"id":"title","value":"stale-or-injected"}`. `ebp-client--notification-dispatcher` sees `authenticated-p` true, runs `ebp-client--handle-state-changed`, which `puthash`es the value into `input-values` (ebp.el:951) and fires every `state-changed-function` (ebp.el:953-955). The application's step-3 surface push can then be seeded from a notification the SPEC says must be logged and dropped — exactly the replayed/stale-state vector §23.4 guards. Symmetrically, an `edit.complete` request arriving in `syncing` is dispatched and answered `1201 content-invalid`/`editor-stale` (ebp.el:1037) instead of `1204 session-state`.

**Proposed fix:** Carry each registered method's legal-state set alongside its handler (projected from `contract.json`'s method table, matching §11). In `ebp-client--request-dispatcher`, after the pre-auth 1200 gate, check `(memq (ebp-client-state client) (method-states m))` and signal `ebp-client--error client 1204 "Method not legal in this state" "session-state"` when it fails. In `ebp-client--notification-dispatcher`, log and drop instead of dispatching. Update `ebp-test-inbound-fails-closed-before-auth` to assert `state.changed` is dropped in `syncing` and adopted only in `ready`, and add a case asserting 1204 for an R-only inbound request during SYNCING.

## [P2] [unverified] §10.1 — ebp.el has no post-authentication §10.1 state gate: READY-only requests and notifications arriving during SYNCING are executed instead of receiving 1204 / being dropped

**Location:** `emacs/ebp.el`:764  
**SPEC line:** 751  
**Auditor:** Audit SS10 (session lifecycle and negotiation) — states, the welcome m

**SPEC quote:**
> After authentication, a method illegal in the current state MUST receive `1204 session-state` when it is a request and MUST be logged and dropped when it is a notification.

**Detail:** ebp-client--request-dispatcher (ebp.el:764) gates only on ebp-client--authenticated-p (ebp.el:755), which returns t for both `syncing` and `ready`; it then dispatches straight to the registered handler, or -32601 when none is registered. ebp-client--notification-dispatcher (ebp.el:782) is the same shape. Neither consults the §11 registry's legal-state column, and there is no method/state table anywhere in ebp.el (the file is the entire Emacs endpoint — `ls emacs/` shows only ebp.el, and grep shows the string "1204" never appears in it). Per §11, `edit.complete` is a Companion->Emacs request legal only in R, and `state.changed`, `edit.open`, `edit.delta`, `edit.caret`, `edit.close` are Companion->Emacs notifications legal only in R — every one of them is registered as a handler in ebp-client-create (ebp.el:543-559) and will therefore run during SYNCING. The Kotlin side implements exactly this gate for both classes (CompanionEngine.kt:403 for the 1204 request path, CompanionEngine.kt:701 `if (state !in spec.states) return` for the notification path, added after the W7 audit); the Emacs side never got the mirror, and no ERT covers it (test/ebp-wire-test.el has no SYNCING-window dispatch case).

**Failure scenario:** Emacs is in SYNCING — a window that in ebp.el lasts from ebp-client--step 'welcome-verified (ebp.el:684) until the session.ready response, bounded only by the 300 s queue.replay timeout at ebp.el:707. A peer (a nonconforming or compromised Companion; §10.1's fail-closed rule exists precisely for this) emits `state.changed {surface:"app:main", revision_seen:41, id:"title", value:"attacker"}`. ebp-client--notification-dispatcher sees authenticated-p = t, finds the registered handler, and ebp-client--handle-state-changed (ebp.el:941) puthashes the value into ebp-client-input-values and runs every state-changed hook — overwriting the input_state the welcome merge just wrote at ebp.el:675-681 and doing it before the barrier's step-3 surface push has reflected the retained draft. SPEC requires the notification be logged and dropped. Likewise an `edit.complete` request in SYNCING runs ebp-client--handle-edit-complete (ebp.el:1026) and returns a completion result instead of the required 1204 session-state error.

**Proposed fix:** Add a method->legal-states table to ebp.el mirroring the §11 registry (the Kotlin METHOD_REGISTRY). In ebp-client--request-dispatcher, after the 1200 pre-auth check, look the method up and signal (ebp-client--error client 1204 "Not legal in this session state" "session-state") when (ebp-client-state client) is not in its state set. In ebp-client--notification-dispatcher, add the same lookup and `message`+return (no reply) when the state is illegal. Add ERT cases feeding state.changed and edit.complete during SYNCING.

## [P2] [unverified] §10.1 — DeviceBridge terminates the live authenticated session when any local process merely opens a TCP connection, before authentication

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/DeviceBridge.kt`:129  
**SPEC line:** 753  
**Auditor:** Audit SS10 (session lifecycle and negotiation) — states, the welcome m

**SPEC quote:**
> When a new session authenticates successfully, the Companion MUST terminate the older session before the new session enters `SYNCING`. [§5.2, line 337]  Authentication failure, timeout, framing failure, transport loss, explicit replacement by a newer authenticated session, and local shutdown MAY transition directly from any state to `CLOSED`. [§10.1, line 753]

**Detail:** The accept loop is: `val socket = server.accept()` (line 127); `current?.runCatching { close() }` (line 129); `current = socket` (line 130); then serve(socket). The old socket is closed at accept time — before session.hello, before auth.response, before any proof is verified. Closing the socket unwinds the old engine's reader into CompanionEngine.close() (CompanionEngine.kt:122-150), which returns the in-flight durable record to queued, dismisses every outstanding dialog, dismisses every pie menu, closes every editor session, and detaches the firing service's LiveSession. serve() then also publishes the *unauthenticated* new engine as the process-wide live session (`CompanionStores.setLiveSession(engine)`, DeviceBridge.kt:250) that cold receivers (reminder tap, trigger drop delivery) route through. §5.2 conditions supersession on successful authentication and §10.1's enumeration of legal CLOSED causes names only "explicit replacement by a newer authenticated session".

**Failure scenario:** Emacs is connected and READY with an outstanding dialog.show and a synchronized editor open. A co-resident Android app (or any local process — §23.6 is explicit that the loopback profile's only defense is the §9 handshake) does `socket = connect(127.0.0.1, 8765)` and sends nothing at all. DeviceBridge line 129 closes Emacs's socket: the dialog request dies unanswered, the editor session is destroyed, the in-flight event.action returns to the queue, and Emacs sees transport loss. The attacker's socket, which will never authenticate, now occupies `current` and the CompanionStores live-session slot. Looping this connect makes the EBP endpoint permanently unusable, with zero pairing knowledge required.

**Proposed fix:** Do not close `current` at accept. Accept the new socket into a pending slot and let its engine run the handshake; supersede the previous session only from the AUTH_VERIFIED transition (a callback the engine fires after handleAuth's proof check succeeds and before it enters SYNCING), closing the prior socket and calling CompanionStores.setLiveSession there rather than in serve(). Bound the number of simultaneously pending unauthenticated sockets and apply the §10.1 handshake close deadline to them.

## [P2] [unverified] §10.2 — ebp.el never gates its capability-scoped senders on `granted`: the welcome's grant set is stored and never read, so Emacs invokes ungranted §11 methods

**Location:** `emacs/ebp.el`:662  
**SPEC line:** None  
**Auditor:** Audit SS11 (method registry) and SS12 (versioning and compatibility). 

**SPEC quote:**
> `wants` is the set of optional capabilities requested by Emacs. `granted` MUST
be its intersection with the Companion's supported capability set. Unknown
requested capabilities MUST be omitted from `granted`. Emacs MUST NOT invoke a
capability-gated method or emit capability-gated content unless the capability
was granted.

**Detail:** `ebp-client--on-welcome` absorbs the grant set at emacs/ebp.el:662 (`(setf (ebp-client-granted client) (plist-get result :granted) (ebp-client-profiles client) (plist-get result :surface_profiles) ...)`). A repo-wide grep for `granted` in emacs/ebp.el returns exactly four hits: the struct slot declaration (:498), that one `setf` (:662), and two doc-comment mentions (:499, :1205). The slot is written and never read; `profiles` likewise. Every §11 capability-gated sender in ebp.el therefore transmits unconditionally:

- `ebp-client-toast` :1141-1146 -> `toast.show` (§11 cap `presentation.toast`, SPEC.md:934)
- `ebp-client-theme-set` :1151-1163 -> `theme.set` (cap `theme`, SPEC.md:936)
- `ebp-client-reminders-set` :1166-1178 -> `reminders.set` (cap `reminders.owner`, SPEC.md:937)
- `ebp-client-capability-invoke` :1187-1199 -> `capability.invoke` (cap `capabilities`, SPEC.md:948)
- `ebp-client-triggers-set` :1208-1224 -> `triggers.set` (cap `triggers`, SPEC.md:949)
- `ebp-client-pie-menu-show` :1228-1239 / `-dismiss` :1240-1241 -> `pie_menu.*` (cap `presentation.pie-menu`, SPEC.md:934-935)
- `ebp-client-dialog-show` :1245-1258 -> `dialog.show` (cap `surfaces.dialog`, SPEC.md:932)
- `ebp-client-edit-apply` :1045-1067 / `ebp-client-edit-resync` :1068-1085 -> `edit.apply`/`edit.resync` (cap `editor.sync`, SPEC.md:942-943)
- `ebp-client-surface-update` :1115-1132 -> `surface.update` for any namespace, without consulting `surface_profiles`, even though §13.1 (SPEC.md:1004-1005) makes a non-`app:` namespace capability-gated.

This is not the deferred application layer: §24.2 (SPEC.md:3447) lists "explicit capability and per-target node, builtin, and feature gating" as an Emacs CORE conformance duty, and these sender functions are the endpoint's own public API in ebp.el. ebp.el does not even export a `granted-p` predicate for a caller to gate on. Contrast the Companion, which gates every one of these at the receive side (CompanionEngine.kt:734, 759, 870, 1004, 1064, 1209, 1253, 1319, 1339, 1371, 1403).

**Failure scenario:** Emacs connects with `:wants '("theme")`; the Companion's welcome returns `granted: ["theme"]` (its `supportedCapabilities` intersection, CompanionEngine.kt:1537). The application then calls `(ebp-client-dialog-show client "confirm" spec :callback cb)`. ebp.el sends the `dialog.show` request with no gate; the Companion's `handleDialogShow` (CompanionEngine.kt:1403-1404) answers `-32601 Method not found`. The §10.2 MUST NOT is violated by the transmission itself, and the caller's callback receives a bare -32601 that is indistinguishable from genuine version skew. Same for `(ebp-client-triggers-set ...)` without `triggers` granted, `(ebp-client-toast ...)` without `presentation.toast`, and `(ebp-client-surface-update client "widget:home" spec)` without `surfaces.widget` — the last additionally burns a per-surface revision, because `ebp-client--surface-request` claims and stores `revision` at emacs/ebp.el:1102-1103 BEFORE sending, so the Emacs-side monotonic counter advances on a request that can never apply.

**Proposed fix:** Add `(defun ebp-client-capability-granted-p (client cap) (and (member cap (append (ebp-client-granted client) nil)) t))` and a private `ebp-client--require-cap` that signals (or returns nil with a `message`) when the capability is absent. Call it at the top of each sender listed above with its §11 capability. For `ebp-client-surface-update`, derive the namespace from the surface-ID prefix and require the matching `surfaces.notification`/`widget`/`tile` grant plus a `surface_profiles` entry for that target, refusing before the revision is claimed at :1102. Leave `ebp-client-surface-remove` ungated (§13.1/§10.4 keep removal legal for welcome-reported surfaces). Also expose the absorbed `surface_profiles` through an accessor so the application layer can perform its §24.2 node/builtin/feature gate.

## [P2] [unverified] §10.2 — ebp.el never gates outbound capability-gated methods on `granted` — the welcome's grant set is stored and never read

**Location:** `emacs/ebp.el`:1245  
**SPEC line:** 840  
**Auditor:** Audit SS10 (session lifecycle and negotiation) — states, the welcome m

**SPEC quote:**
> Emacs MUST NOT invoke a capability-gated method or emit capability-gated content unless the capability was granted.

**Detail:** `granted` is absorbed into the client struct at ebp.el:662 and never consulted again: grep for "granted" over emacs/ebp.el returns only the struct slot declaration (line 498), the required-member list (641), the setf at 662, and two doc-string mentions. Every module sender emits unconditionally — ebp-client-dialog-show (1245, gated on `surfaces.dialog`), ebp-client-toast (1141, `presentation.toast`), ebp-client-theme-set (1151, `theme`), ebp-client-reminders-set (1166, `reminders.owner`), ebp-client-capability-invoke (1187, `capabilities`), ebp-client-triggers-set (1208, `triggers`), ebp-client-pie-menu-show/dismiss (1227/1239, `presentation.pie-menu`). §24.2 lists "explicit capability and per-target node, builtin, and feature gating" as an Emacs core conformance MUST, and REWRITE-PLAN assigns "module method plumbing (dialogs, editor sync, triggers, capabilities)" to ebp.el, so this is endpoint duty, not application duty. The same functions also carry no session-state gate: ebp-client-toast will emit a READY-only notification while the client is still `connected`/`awaiting-nonce`, which §10.1's CONNECTED row ("Emacs MAY send only `session.hello`") forbids — ebp-connect (1266) returns the client to the caller immediately after ebp-client-start, while the handshake is still in flight.

**Failure scenario:** An application connects with :wants '("theme") (or the Companion simply does not support surfaces.dialog). The welcome carries granted=["theme"]. The application then calls ebp-client-dialog-show; ebp.el emits `dialog.show` on the wire with no check, violating the MUST. CompanionEngine.handleDialogShow answers -32601 method-not-found (CompanionEngine.kt:1403-1404) and the user gets no dialog and no local diagnostic that the capability was never negotiated. Same shape for ebp-client-theme-set / toast / pie_menu: those are notifications, so the Companion drops them silently (CompanionEngine.kt:1339, 1371, 734) and Emacs never learns the content was discarded. In the state variant, an application that calls ebp-client-toast immediately after ebp-connect emits toast.show while the Companion is still in CONNECTED, where handleNotification returns unconditionally (CompanionEngine.kt:695).

**Proposed fix:** Add (ebp-client--require-capability client CAP) and (ebp-client--require-state client STATES) helpers. Have each module sender call the pair first and signal a local elisp error (or return nil with a `message`) rather than putting the frame on the wire — dialog.show/theme.set/toast.show/pie_menu.*/reminders.set/capability.invoke/triggers.set gated on their §11 capability column and their S/R state column. Add ERT cases asserting that an ungranted sender emits no frame.

## [P2] [unverified] §10.2 — Welcome `surface_profiles` is session-independent: the REQUIRED `app` profile advertises the `trigger.fire` builtin even when `triggers` was not granted

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1546  
**SPEC line:** 846  
**Auditor:** Audit SS10 (session lifecycle and negotiation) — states, the welcome m

**SPEC quote:**
> Each profile MUST contain distinct `node_types`, `builtins`, and `features` arrays and MUST list exactly what the Companion will honor on that target during this session.

**Detail:** buildWelcome emits `.put("surface_profiles", config.surfaceProfiles)` verbatim (CompanionEngine.kt:1546); config.surfaceProfiles is the static NodeSupport.surfaceProfiles() object (DeviceBridge.kt:66, NodeSupport.kt:76-82), whose APP_BUILTINS set unconditionally contains "trigger.fire" (NodeSupport.kt:57-60). Nothing filters it by the per-session `granted` list computed two lines earlier (CompanionEngine.kt:1533). But the Companion will not honor `trigger.fire` in a session without `triggers`: executeBuiltin (CompanionEngine.kt:228-232) does `if ("triggers" !in granted) return` — a silent no-op. §14.2 (line 1301) reinforces this: "`clipboard.copy`, `share.send`, and `trigger.fire` are OPTIONAL and MUST be positively advertised in each profile where they are usable; `trigger.fire` additionally requires the `triggers` capability and a registered `manual` trigger." SpecValidator's builtin check (SpecValidator.kt:923-928) resolves the name against the global ACTION_SCHEMA only, so the surface is accepted with no error either. (The same static object also emits complete `dialog` and `notification` profiles when neither surfaces.dialog nor surfaces.notification was granted — see the companion SPEC finding on whether omission is mandatory there.)

**Failure scenario:** Emacs sends `session.hello` with wants=["theme"]. granted=["theme"]. The welcome's surface_profiles.app.builtins nevertheless contains "trigger.fire". Emacs does exactly what §10.2 line 848 commands — "Emacs MUST gate every emitted node, builtin, and constraining feature against the target profile" — sees trigger.fire advertised, and authors a button whose on_tap is {builtin:"trigger.fire", id:"capture"}. surface.update returns status "applied" (the validator only checks that the builtin name is globally known). The user taps the button: executeBuiltin returns at CompanionEngine.kt:231 without firing, without an event.action, and without any error or log.error. A permanently dead control that both endpoints believe is live.

**Proposed fix:** Build the welcome's surface_profiles per session rather than passing config.surfaceProfiles through: copy the static object and remove capability-conditional builtins that were not granted (`trigger.fire` when "triggers" not in granted), the same way buildWelcome already scrubs the device report's trigger-only members at lines 1561-1571. Add a wire test asserting that with wants=[] the app profile's builtins array does not contain trigger.fire.

## [P2] [unverified] §10.4 — Companion never persists the READY-disconnection time, and no surface-disconnection staleness timer exists for §10.3 to clear

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:122  
**SPEC line:** 912  
**Auditor:** Audit SS10 (session lifecycle and negotiation) — states, the welcome m

**SPEC quote:**
> When a `READY` connection closes, the Companion MUST persist the disconnection time before accepting new offline interactions. If the Companion itself restarts while disconnected, it MUST restore that time or conservatively use the earliest time it can prove.

**Detail:** CompanionEngine.close() (line 122-150) clears the in-flight marker, dismisses dialogs and pie menus, closes editors and detaches the firing service — it records no timestamp. A grep for disconnect/staleness/stale_after/disconnectedAt over companion/wire/src/main and companion/app/src/main returns no match outside unrelated trigger `power` predicates. The dependent state is missing too: handleSurfaceUpdate (CompanionEngine.kt:590-596) reads only `spec`, `stale_spec`, `current_view` and `reset_input_ids` from the params — `stale_after_s` is never read at all — and SurfaceStore.update validates `staleSpec` (SurfaceStore.kt:140, 156) but its Record class (SurfaceStore.kt:32-38) has no field to hold it, so the validated stale_spec is discarded. Consequently §10.3's "The Companion MUST then clear the surface-disconnection staleness timer" (line 889) is vacuous in the session.ready handler (CompanionEngine.kt:415-438), and §13.5's "its clock starts when the preceding `READY` session disconnects, MUST survive Companion process death, and ends only when a new session reaches `READY`" has no implementation. This is not a deferred rung: REWRITE-PLAN puts reconnection in W3 and surfaces in W4, both marked done; only §22 traffic classes are W10.

**Failure scenario:** Emacs pushes `app:agenda` with `stale_after_s: 300` and a `stale_spec` that replaces the action buttons with a "disconnected — data may be out of date" panel. The session reaches READY, then the laptop lid closes and the connection drops. CompanionEngine.close() records nothing. Two hours later the user opens the Companion: store.spec("app:agenda") returns the primary spec and DeviceBridge's surfaceListener renders it unchanged (DeviceBridge.kt:253-262) with no staleness indication and no stale_spec substitution, because the stale_spec was thrown away at accept time and there is no disconnection timestamp to compare against. The user acts on two-hour-old agenda data presented as current. After a Companion process restart the situation is unrecoverable by design — there is no persisted time to restore and no "earliest time it can prove" fallback.

**Proposed fix:** Persist a per-pairing `disconnected_at_ms` (alongside the surface backing, written from CompanionEngine.close() when state was READY, and lazily on first offline interaction if the process died) and clear it in the session.ready handler when entering READY. Store `stale_after_s` and `stale_spec` on SurfaceStore.Record and in PersistedRecord so they survive process death, and have DeviceBridge.resolveView consult (now - disconnected_at_ms) >= stale_after_s*1000 to select stale_spec / show the staleness indication. On restart with no persisted time, use the earliest provable time (e.g. the surface backing file's last-modified time) rather than treating the surface as fresh.

## [P2] [unverified] §12 — `capability.invoke` and `triggers.set` reject unknown optional params members, breaking §12's must-ignore rule for objects the SPEC never declares closed

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1066  
**SPEC line:** None  
**Auditor:** Audit SS11 (method registry) and SS12 (versioning and compatibility). 

**SPEC quote:**
> 1. A receiver MUST ignore an unknown optional member unless the object's
   section requires whole-object rejection.

**Detail:** `handleCapabilityInvoke` opens with `for (k in params.keySet()) if (k != "cap" && k != "args") return respondError(id, -32602, "Invalid params", "invalid-params")` (CompanionEngine.kt:1066-1067). `TriggerValidator.validateSet` does the same for `triggers.set`: `for (k in params.keySet()) if (k != "triggers") throw ContentInvalid(k, "unknown member")` (TriggerValidator.kt:53-54), which `handleTriggersSet` maps to 1101.

Neither §20.2 nor §21.1 requires whole-object rejection of the METHOD PARAMS object. §20.2 (SPEC.md:2749) says only "Params are `{cap, args?}`"; the word "closed" appears in §20.3 (SPEC.md:2774) scoped strictly to the catalog's Args and Result objects — which CapabilityCatalog.kt:112 correctly enforces separately. §21.1 (SPEC.md:2899) says "A trigger ENTRY is a closed object" and §21.5 (SPEC.md:3068) says "Every trigger params object and predicate is closed" — both about nested objects, both correctly enforced at TriggerValidator.kt:359. The SPEC uses the word "closed" eleven times and never applies it to a method's params wrapper.

The SPEC also demonstrates the opposite rule explicitly for the two handshake methods, proving that enumerating members in a params table does NOT close the object: §9.2 (SPEC.md:649) "Unknown optional hello members MUST be ignored under Section 12" and §9.3 (SPEC.md:704) "Extra optional members MUST be ignored." §12 (SPEC.md:967) further guarantees "New optional cosmetic fields MAY be added without a major bump" — the exact growth path these two strict-key loops break. §12 rules 2-3 already confine an unnegotiated added member to non-constraining/cosmetic content, so ignoring it is safe by construction. Note the surface methods get this right: `handleSurfaceUpdate`/`handleSurfaceRemove` read only known members and ignore the rest.

**Failure scenario:** A conforming EBP-2 Emacs of a later revision adds the cosmetic optional member `trace_id` (a §12-legal non-constraining growth within major 2) and sends `{"jsonrpc":"2.0","id":"c1","method":"capability.invoke","params":{"cap":"vibrate","args":{"ms":200},"trace_id":"a7f3"}}`. This Companion returns `-32602 Invalid params` at CompanionEngine.kt:1066 and the device never vibrates, although §12 rule 1 requires `trace_id` to be ignored and the invocation performed. Identically, `{"method":"triggers.set","params":{"triggers":[...],"trace_id":"a7f3"}}` throws `ContentInvalid("trace_id","unknown member")` at TriggerValidator.kt:54 and the whole replace-set is rejected with 1101 — an atomic rejection of a fully valid trigger set.

**Proposed fix:** Delete the two strict-key loops (CompanionEngine.kt:1066-1067 and TriggerValidator.kt:53-54) and read only the defined members, as `handleSurfaceUpdate`/`handleSurfaceRemove` already do. Keep the closed-object enforcement where the SPEC actually declares it: CapabilityCatalog.kt:112 (Args/Result), TriggerValidator.kt:359 (trigger entry / params / predicate), CompanionEngine.kt:910 (reminder entry). Optionally amend §12 to add an explicit sentence — "A method's top-level `params` object is extensible under rule 1 unless its section declares it closed" — so the boundary between the closed nested schemas and the extensible params wrapper is stated once rather than inferred.

## [P2] [unverified] §13.2 / §13.3 — surface.update / surface.remove answer "applied" after a swallowed durable-write failure

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SurfaceStore.kt`:68  
**SPEC line:** 1051  
**Auditor:** Audit SS13.1 through SS13.4 (surface namespaces, surface.update / surf

**SPEC quote:**
> If `revision` is greater than the stored snapshot or tombstone revision, the Companion MUST persist and atomically present the snapshot, then return: (SPEC.md:1050-1051)  ...  If the removal revision is newer than the stored floor, the Companion MUST remove the visible and cached snapshot, persist a tombstone at that revision, and return `{status:"applied", revision, present:false}`. (SPEC.md:1076-1079)

**Detail:** `persist()` wraps the whole durable write in `runCatching { ... }` with no failure branch (SurfaceStore.kt:68-76), so an IOException from FileSurfaceBacking.replace (write, fsync, or the atomic rename that explicitly `throw java.io.IOException("atomic replace failed")`, SurfaceBacking.kt:92-99) is discarded. update() then returns SurfaceResult("applied", revision, true) at line 197 and remove() returns SurfaceResult("applied", revision, false) at line 219 regardless. The in-memory record has already been mutated at lines 190-194 / 210-215, so there is no rollback either. The sibling store gets this right: DurableQueue.admit snapshots its state, calls persist() inside try/catch and on failure restores it and returns AdmitResult.StorageFailed, with the comment "SPEC 15.1: storage failure MUST NOT claim the queueing" (DurableQueue.kt:139-155). Surfaces make the opposite choice for an equally explicit persist-then-return MUST.

**Failure scenario:** The device's data partition is full. Emacs sends surface.remove {surface:"app:inbox", revision:42}; the in-memory record is tombstoned, FileSurfaceBacking.replace throws ENOSPC, runCatching eats it, and the Companion answers {status:"applied",revision:42,present:false}. Emacs treats the surface as retired (it absorbs floor 42 and stops pushing it). The Companion process is then killed; on restart SurfaceStore.init reads the last good file, in which app:inbox is still present at revision 41 — the removed surface is rendered again from the stale cache and is reported present in the next welcome, contradicting the applied removal Emacs was promised. The same hole makes an "applied" update durably a no-op.

**Proposed fix:** Make persist() throw, and have update()/remove() snapshot the mutated Record (and the drafts they touched), call persist() inside try/catch, restore the snapshot on failure, and surface the failure to the caller so handleSurfaceUpdate/handleSurfaceRemove answer an error instead of "applied" — mirroring DurableQueue.admit's AdmitResult.StorageFailed rollback.

## [P2] [unverified] §13.2 / §13.4 — Wrong-typed current_view / reset_input_ids / stale_spec are silently ignored instead of rejected with 1201

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:595  
**SPEC line:** 1045  
**Auditor:** Audit SS13.1 through SS13.4 (surface namespaces, surface.update / surf

**SPEC quote:**
> The Companion MUST validate the entire request before changing persistent or visible state. If the content is invalid, it MUST return `1201 content-invalid`, MUST leave the previous snapshot unchanged, and SHOULD name the failing object path in `error.data.path`. (SPEC.md:1045-1048)  ...  An update's optional `current_view` MUST name an existing view. (SPEC.md:1115-1116)

**Detail:** handleSurfaceUpdate reads the three optional members with silently-narrowing accessors: `params.optJSONObject("stale_spec")`, `params.opt("current_view") as? String`, `params.optJSONArray("reset_input_ids")` (CompanionEngine.kt:594-596). Every one of them yields null — i.e. "member absent" — when the member is PRESENT but of the wrong JSON type. SurfaceStore.update then takes the absent-branch: `if (currentView != null)` (SurfaceStore.kt:158) never fires, `resetIds?.let { validateResetIds(...) } ?: emptySet()` (154-155) yields an empty reset set, and `staleSpec?.let { validateStaleSpec(...) }` (156) is skipped. The update is applied and answered {status:"applied"}. This is the same wrong-typed-member class the W7 audit found in the notification meta path (`meta.actions`, `meta.chronometer`) and that RB-6 fixed there — the core §13.2 request path still has it. Note the element-level types ARE checked (validateResetIds rejects a non-string element, SpecValidator.kt:136-137), so only the container type escapes.

**Failure scenario:** (1) Emacs pushes {surface:"app:main", revision:8, spec:<multi-view>, current_view:5} (a nonconforming or version-skewed sender emitting a number/symbol where an identifier belongs). §13.4 requires 1201 content-invalid because 5 does not name an existing view; the Companion instead returns {status:"applied",revision:8,present:true} and leaves the user on whatever view was already showing, so Emacs believes it navigated the device and the device did not move. (2) Emacs pushes {..., reset_input_ids:"title"} intending to discard a rejected draft; the Companion applies the update, keeps the user's dirty draft for `title` (reconcileDrafts is called with an empty reset set), and republishes that draft in the next welcome `input_state` — while ebp.el has already recorded the reset in its reset-history (ebp.el:1132) and will discard the racing state.changed, leaving the two sides permanently disagreeing about the field's value.

**Proposed fix:** In handleSurfaceUpdate, type-check each optional member before use: if `params.has("current_view")` and `params.opt("current_view") !is String` -> 1201 with path "current_view"; likewise `stale_spec` must be a JSONObject and `reset_input_ids` a JSONArray when present. Same treatment for `stale_after_s` (see the separate finding).

## [P2] [unverified] §13.2 / §13.5 (§24.1) — stale_after_s is never read, validated, or persisted — the §13.5 staleness clock does not exist

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:592  
**SPEC line:** 1135  
**Auditor:** Audit SS13.1 through SS13.4 (surface namespaces, surface.update / surf

**SPEC quote:**
> | `stale_after_s` | positive integer | no | Disconnected duration after which stale presentation begins | (SPEC.md:1035)  ...  If present, its clock starts when the preceding `READY` session disconnects, MUST survive Companion process death, and ends only when a new session reaches `READY`. (SPEC.md:1134-1137)

**Detail:** `stale_after_s` appears nowhere in the Kotlin sources (grep over companion/ finds it only in ebp/SPEC.md and emacs/ebp.el:1125, where Emacs sends it). handleSurfaceUpdate reads only surface/revision/spec/stale_spec/current_view/reset_input_ids (CompanionEngine.kt:563-596) and SurfaceStore.update's signature has no stale_after_s parameter at all (SurfaceStore.kt:124-126); PersistedRecord carries only surface/revision/present/spec/current_view (SurfaceBacking.kt:17-23). Consequences: (a) the member is accepted with any JSON type or value, so §13.2's "MUST validate the entire request" is not met for it; (b) no clock is started at disconnect and nothing about it survives process death, so the §13.5 MUST cannot hold; (c) `stale_spec` is validated (SurfaceStore.kt:156) and then discarded, so the specification Emacs supplied for the stale state can never be rendered. §24.1's Companion conformance list names "atomic cached `app:*` surfaces and disconnected staleness semantics" (SPEC.md:3425) as REQUIRED, and no rung of docs/REWRITE-PLAN.md defers it (W10 is only §22).

**Failure scenario:** Emacs pushes {surface:"app:agenda", revision:3, spec:<live agenda>, stale_after_s:0, stale_spec:<"disconnected" card>}. stale_after_s:0 is not a positive integer, so §13.2 requires 1201 content-invalid; the Companion returns {status:"applied"}. With a conforming stale_after_s:300 instead, the user then unplugs the phone: five minutes, an hour, or a week later the device still renders the original agenda with no staleness indication and never swaps in stale_spec, and nothing about the elapsed disconnection survives the process death that Android will impose in that window.

**Proposed fix:** Validate `stale_after_s` in handleSurfaceUpdate (present => Int/Long, >= 1, within the safe-integer range, else 1201 with path "stale_after_s"); thread stale_after_s + stale_spec into SurfaceStore.update and PersistedRecord/FileSurfaceBacking so both survive process death; record a durable disconnect timestamp when a READY session ends, clear it when a new session reaches READY (the engine already has the READY transition at CompanionEngine.kt:415-438), and have the renderer select stale_spec once now - disconnect_at >= stale_after_s.

## [P2] [CONFIRMED] §13.4 — surface.update silently ignores wrong-typed reset_input_ids/stale_spec/current_view and never validates stale_after_s at all

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:594  
**SPEC line:** 1099  
**Auditor:** Audit SS13.5 and SS13.6 (input state, drafts, draft reconciliation on 

**SPEC quote:**
> `stale_spec`, when supplied, MUST use the same variant as `spec`.
`current_view` is valid only for a multi-view `app:*` spec. Any other
combination MUST receive `1201 content-invalid`.

**Detail:** handleSurfaceUpdate reads the three optional members with silently-coercing accessors: `params.optJSONObject("stale_spec")` (line 594), `params.opt("current_view") as? String` (line 595), `params.optJSONArray("reset_input_ids")` (line 596). org.json's optJSONObject/optJSONArray return null for a present-but-wrong-typed member, and `as? String` yields null the same way, so a supplied-but-malformed member is indistinguishable from an absent one and SurfaceStore.update takes the it-was-omitted path: no §13.5 stale_spec validation, no §13.4 current_view check, and — the §13.6-relevant case — `reset = emptySet()` at SurfaceStore.kt:155, so reconcileDrafts never clears the ids Emacs asked it to clear, yet the result is {status:"applied"}. Separately, `stale_after_s` is never read anywhere in the Kotlin tree (grep over companion/**/*.kt returns zero hits; the only occurrence in the repo is the elisp sender at emacs/ebp.el:1125), so the §13.2 table's "positive integer" type is unenforced and §13.5's whole staleness clock is inert: stale_spec is validated and then discarded (SurfaceStore.update never stores it — Record has no staleSpec field), so "If `stale_spec` is present, it SHOULD render that complete specification instead" can never occur.

**Failure scenario:** Emacs (or any version-skewed sender) sends surface.update {surface:"app:main", revision:2, spec:{...text_input id:"title"...}, reset_input_ids:"title", stale_after_s:-1}. reset_input_ids is a string, not an array, so optJSONArray returns null; stale_after_s is negative and is never inspected. The Companion returns {status:"applied", revision:2, present:true}. The user's dirty draft for "title" is silently retained (compatible under §13.6), so capture_fields and the next welcome input_state still report the draft Emacs believed it had replaced — while §13.2 requires the whole request to be rejected with 1201 content-invalid and the previous snapshot left unchanged.

**Proposed fix:** Read each optional member with an explicit presence-then-type check and raise ContentInvalid (path = the member name) when present with the wrong type: `if (params.has("reset_input_ids") && params.opt("reset_input_ids") !is JSONArray) → 1201`, likewise for stale_spec (must be JSONObject) and current_view (must be String). Add stale_after_s validation (present ⇒ positive safe integer) and thread it into SurfaceStore.update so the §13.5 clock has something to persist.

**Verdicts:**
- `SPEC TEXT` refuted=False (high): The quote is verbatim, normative body text, and unamended. SPEC.md:1099-1101 reads exactly "`stale_spec`, when supplied, MUST use the same variant as `spec`. / `current_view` is valid only for a multi-view `app:*` spec. Any other / combination MUST receive `1201 content-invalid`." — plain §13.4 prose, not a note or example, MUST-level, and addressed to the receiving Companion. SPEC-CHANGES.md (ame
- `CODE TRUTH` refuted=False (high): Reproduced by reading. CompanionEngine.kt:593-596 passes `params.optJSONObject("stale_spec")`, `params.opt("current_view") as? String`, `params.optJSONArray("reset_input_ids")` — all yield null for a present-but-wrong-typed member. No earlier gate: handleRequest only rejects a non-object `params` (-32602) and METHOD_REGISTRY carries sender/class/state, not a param schema; dispatch (line 159) types

## [P2] [unverified] §13.4 (with §4.4) — Multi-view `views` keys are never validated as identifiers

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:106  
**SPEC line:** 1115  
**Auditor:** Audit SS4.1 through SS4.4 (JSON data model: value types, object/duplic

**SPEC quote:**
> `views` MUST be a non-empty object whose keys are identifiers and whose values are root Nodes.

**Detail:** `validateSurfaceSpec` (SpecValidator.kt:98-111) checks that `views` is a non-empty object, that `initial_view` names an existing key, and that each value is a node — but the loop `for (name in views.keySet())` never tests `name` against the §4.4 grammar or the §4.5 128-octet cap. Nothing downstream compensates: `SurfaceStore.update` only asks `spec.getJSONObject("views").has(currentView)` (SurfaceStore.kt:159, 185) and `switchView` only asks `views.has(view)` (SurfaceStore.kt:99), both pure membership tests. The chosen view name is then written into the durable backing as `PersistedRecord.currentView` (SurfaceStore.kt:71) and echoed through the §14.2 `view.switch` builtin.

**Failure scenario:** Emacs pushes `surface.update` for `app:main` with `{"views":{"":{"t":"text","text":"x"}},"initial_view":""}`. §4.4 requires an identifier to contain 1 through 128 ASCII characters, so the empty key is not an identifier and the document MUST be rejected with 1201. Instead it is accepted, `current_view` becomes "", and that empty name is persisted and used as the surface's navigation state. The same acceptance covers a 200-character key or one containing spaces/newlines, which then round-trips to Emacs in `view.switch` args as a value §4.4 promises is an identifier.

**Proposed fix:** In the `spec.has("views")` branch, before `walkNode`, reject any key that fails the shared `isIdentifier()` test: `if (!isIdentifier(name)) throw ContentInvalid("$path.views.$name", "view name must be an identifier")`. Apply the same check to `initial_view` and to `current_view` in SurfaceStore.update.

## [P2] [unverified] §14.1 — max_field_bytes is never enforced on dialog-captured field values

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1449  
**SPEC line:** 1246  
**Auditor:** Audit SS18.1 through SS18.3 (dialogs incl. the dialog.show request and

**SPEC quote:**
> It MUST enforce `max_field_bytes` while accepting user input and MUST NOT create an occurrence whose captured field exceeds that limit; it SHOULD expose a local validation diagnostic instead.

**Detail:** §14.2's dialog.submit row (SPEC.md:1284) says "`capture_fields` obeys Sections 14.1 and 14.6", and §4.5 (SPEC.md:231) defines max_field_bytes as the "maximum encoded bytes per input value, including a volatile password value". Nothing in the dialog path applies it. completeDialogSubmit checks only the aggregate prospective frame against WireLimits.MAX_BODY_OCTETS (CompanionEngine.kt:1447-1452); onButton copies each captured value verbatim with no size test (Renderer.kt:533-539); and RenderTextInput sets no length bound on the OutlinedTextField (Renderer.kt:262-289). A repo-wide grep for max_field_bytes/MAX_FIELD_BYTES shows the only enforcement site is the notification inline-reply path (ContextlessEvents.kt:125-131) — the dialog and surface capture paths were never given the same guard. So any dialog field between max_field_bytes (65,536 in the reference config, DeviceBridge.kt:71) and max_frame_bytes (4,194,304) is accepted and transmitted, defeating the whole point of a per-value bound the Companion advertised in its welcome.

**Failure scenario:** Dialog spec {t:"column",children:[{t:"text_input",id:"note"},{t:"button",label:"OK",on_tap:{builtin:"dialog.submit",capture_fields:["note"]}}]}. The user pastes a 200,000-character clipping and taps OK. The prospective response body is ~200 KB, far under max_frame_bytes, so the size gate at line 1449 passes and the Companion answers {"status":"submitted","fields":{"note":"<200000 chars>"}} — a single input value more than 3x the advertised max_field_bytes, with no local validation diagnostic shown.

**Proposed fix:** Enforce max_field_bytes at both ends: cap accepted input per stateful node in the renderer (a maxLength derived from the advertised limit, with a local diagnostic), and in completeDialogSubmit reject/hold the submit when any member of `fields` exceeds config.limits.max_field_bytes in UTF-8 octets, routing it through the existing dialogOverflowListener so the dialog stays outstanding and any password attempt is concluded per §14.6.

## [P2] [CONFIRMED] §14.1 — `max_field_bytes` is never enforced on captured fields — an over-limit occurrence is created and sent/persisted

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:273  
**SPEC line:** 1245  
**Auditor:** Audit SS14.1 through SS14.3 (ActionDescriptor shape, the dotted action

**SPEC quote:**
> It MUST enforce
`max_field_bytes` while accepting user input and MUST NOT create an occurrence
whose captured field exceeds that limit; it SHOULD expose a local validation
diagnostic instead.

**Detail:** `grep -rn 'max_field_bytes\|maxFieldBytes' companion/ --include=*.kt` shows the limit is only ever consumed by AppCapabilities.readClipboard (§20.3, AppCapabilities.kt:86) and ContextlessEvents' notification inline reply (§18.5, ContextlessEvents.kt:128), plus the startup floor/consistency checks in CompanionEngine.kt:1594/1599. The §14.1 capture path never reads it: dispatchAction builds `fields` at CompanionEngine.kt:273-285 by copying `surfaces.currentValue(surface, fieldId)` verbatim with no per-field size check, and the only size gate is the whole-params `max_event_bytes` check at line 294 — a different, much larger limit (DeviceBridge advertises max_field_bytes 65_536 and max_event_bytes 262_144, DeviceBridge.kt:69-72). The renderer likewise imposes no cap while accepting input: RenderTextInput.onValueChange (Renderer.kt:266-279) strips U+000A for single_line and otherwise accepts arbitrary length, and SurfaceStore.putDraft (SurfaceStore.kt:249-256) persists the draft unbounded. Neither half of the MUST (enforce while accepting input; never create an over-limit occurrence) exists.

**Failure scenario:** An app surface has `{t:"text_input", id:"note"}` and `{t:"button", label:"Save", on_tap:{action:"note.save", when_offline:"drop", capture_fields:["note"]}}`. The user pastes a 100 KB document into the field (65_536 < 100 KB < 262_144). The draft is retained and persisted by putDraft. On tap, dispatchAction copies the full 100 KB into `fields.note`; the params serialize to ~100 KB, which passes the max_event_bytes check at line 294, so the event is transmitted (and, for a `queue` descriptor, committed to the durable queue). The spec requires that no occurrence be created at all and that a local validation diagnostic be shown instead.

**Proposed fix:** Enforce at both ends. In dispatchAction, after building `fields` (before the max_event_bytes check at line 294), iterate the members and, if any value's UTF-8 serialization exceeds `config.limits.getLong("max_field_bytes")`, invoke the callback with the existing 1201 content-invalid shape (`reason="field-too-large"`, plus the offending id in `data`) and return without persisting or sending — mirroring the event-too-large branch at 296-300. In the renderer, cap input at commit: in RenderTextInput.onValueChange (and the editor's `commit`), reject an edit whose resulting UTF-8 byte length would exceed the advertised max_field_bytes, keeping the prior value and surfacing the host's local diagnostic. Add a test that a capture whose value exceeds max_field_bytes but not max_event_bytes emits no `event.action` frame and no queue record.

**Verdicts:**
- `MATERIALITY` refuted=False (high): SPEC.md:1245-1247 ("MUST enforce max_field_bytes while accepting user input and MUST NOT create an occurrence whose captured field exceeds that limit") is unenforced on every path. CompanionEngine.kt:270-302 copies surfaces.currentValue verbatim into `fields` and gates only on max_event_bytes (262_144) at line 294, 4x the advertised max_field_bytes (65_536, DeviceBridge.kt:71); Renderer.kt:266-279
- `CODE TRUTH` refuted=False (high): SPEC.md:1245-1247 ("It MUST enforce `max_field_bytes` while accepting user input and MUST NOT create an occurrence whose captured field exceeds that limit") is unimplemented on the §14.1 path. CompanionEngine.kt:273-285 builds `fields` by copying `surfaces.currentValue(surface, fieldId)` verbatim and merging `extraFields`, and the very next gate is CompanionEngine.kt:294-295 `params.toString().toB
- `SPEC TEXT` refuted=False (high): The quote is verbatim and normative. SPEC.md:1244-1247 (§14.1 body prose — not a note, example, or table caption) reads: "The Companion MUST reject the containing document when a name is absent, duplicated, or non-stateful. It MUST enforce `max_field_bytes` while accepting user input and MUST NOT create an occurrence whose captured field exceeds that limit; it SHOULD expose a local validation diag

## [P2] [unverified] §14.1 (via §18.5) — A notification action's `on_tap.capture_fields` is neither rejected at validation nor honored at tap time

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:268  
**SPEC line:** 1241  
**Auditor:** Audit SS18.5 (notification surfaces: meta, priority monotonicity amend

**SPEC quote:**
> `capture_fields` is valid only for a descriptor inside a surface or dialog containing every named stateful node. Its length MUST NOT exceed `max_capture_fields`. Each name MUST resolve to exactly one stateful node in that document. The Companion MUST reject the containing document when a name is absent, duplicated, or non-stateful.

**Detail:** validateNotificationSpec (SpecValidator.kt:169-189) runs the §14.1 capture_fields resolution only over `spec.body`, through validateSurfaceSpec's ctx.captureRefs pass (SpecValidator.kt:119-124). The §18.5 meta is validated by a separate, shallower path: validateNotificationMeta (SpecValidator.kt:194-227) -> validateNotificationAction (SpecValidator.kt:230-301). That function's only mention of capture_fields is line 268, `if (hasInput && onTap.has("capture_fields"))` — the amendment-mandated inline-reply rule. With no `input`, capture_fields is not length-checked against max_capture_fields, not checked for duplicates, and never resolved against any document. Because NOTIFICATION_NODE_TYPES (NodeSupport.kt:50) is text/row/column/box/spacer/divider, a notification body can contain no stateful node at all (and §16.2 says an unadvertised known type registers no stateful draft), so EVERY capture_fields name on a notification action is necessarily absent and the document MUST be rejected. The mismatch compounds at tap time: dispatchContextless (ContextlessEvents.kt:38-82) never reads capture_fields, so the dispatched event carries no `fields` even though §14.1 requires the selected values be copied into event.action.fields at occurrence time.

**Failure scenario:** Emacs sends `surface.update` for `notification:note` with `meta.actions[0] = {label:"Save", on_tap:{action:"note.save", capture_fields:["draft"], when_offline:"queue", ttl_s:3600}}`. No node named "draft" exists (none can), so §14.1 requires 1201 content-invalid. The Companion instead returns {"status":"applied","revision":N,"present":true} and posts the notification. The user taps Save and Emacs receives an event.action with no `fields` member at all — the occurrence-time fact the action's meaning depends on is silently missing rather than the request having been refused up front.

**Proposed fix:** In validateNotificationAction, reject any capture_fields on a notification action's on_tap with 1201 regardless of whether `input` is present — the correct closed-form rule for a profile whose body can hold no stateful node. If a future profile advertises stateful notification nodes, instead thread the body's stateful map out of validateNotificationSpec and run the same §14.1 length/duplicate/resolution checks validateSurfaceSpec uses, and teach dispatchContextless to snapshot the named values into `fields`.

## [P2] [CONFIRMED] §14.1 (with §18.1) — `dialog.submit` capture_fields returns the empty string for a stateful node the user never touched, instead of that node's current logical value

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt`:537  
**SPEC line:** 1248  
**Auditor:** Audit SS14.1 through SS14.3 (ActionDescriptor shape, the dotted action

**SPEC quote:**
> At occurrence time, the Companion MUST copy all selected
current values into `event.action.fields` as one logical snapshot before any
dependent state can change.

**Detail:** §18.1 (SPEC.md:2219-2221) restates this for dialogs: `fields` "MUST contain exactly the named current values keyed by node ID". DialogContext.fields is created empty (`remember(dialogId) { mutableStateMapOf<String, Any?>() }`, Renderer.kt:114) and is only ever written by RenderCtx.state (Renderer.kt:94), which each input node calls solely from its change callback — RenderCheckbox seeds its local `checked` from the node but calls `ctx.state` only in `onCheckedChange` (InputNodes.kt:185-194); RenderSwitch, RenderEnumList, RenderSlider and RenderTextInput behave the same way. So a stateful dialog node the user never interacts with has no entry in the map. onButton's dialog.submit branch then substitutes a literal empty string: `fields.put(fieldId, dialog.fields[fieldId] ?: "")` (Renderer.kt:537). This is both the wrong value and the wrong JSON type. (Flagged as a P2 in the W7 audit's §18.1 module posture, docs/AUDIT-w7-conformance.md:427; still present at HEAD 36e6706.)

**Failure scenario:** Emacs sends `dialog.show {dialog_id:"prefs", spec:{t:"column", children:[{t:"checkbox", id:"notify", checked:true, label:"Notify me"}, {t:"enum_list", id:"mode", options:[{label:"A",value:"a"}]}, {t:"button", label:"OK", on_tap:{builtin:"dialog.submit", capture_fields:["notify","mode"]}}]}}`. The user accepts the defaults and taps OK. The result is `{status:"submitted", fields:{notify:"", mode:""}}` — `notify` must be the boolean `true` (the node's authored current value) and `mode` must be `null` (§17.4: an omitted single-select value has logical captured value null, and the Companion MUST NOT select the first option implicitly). Emacs's handler reads `""` for a boolean field and either mis-parses it as false or rejects the dialog result.

**Proposed fix:** Seed DialogContext.fields with each stateful node's authored logical value when the dialog tree is first composed, or resolve on read. The value derivation already exists in the wire layer as `SurfaceStore.authoredValue` (SurfaceStore.kt:316-324): text_input/editor → `value ?: ""`, checkbox/switch → `checked ?: false`, enum_list → `value ?: (multi_select ? [] : null)`, slider → `value ?: values[0] ?: min ?: 0`. Hoist it to a shared pure helper in the wire module and have RenderDialogRoot walk the dialog spec once, pre-populating `fields` for every stateful id; then change Renderer.kt:537 to `fields.put(fieldId, dialog.fields[fieldId] ?: JSONObject.NULL)` so an unresolvable id is at least JSON null rather than a coerced string. Add an app-module test asserting an untouched checkbox captures the boolean `true` and an untouched valueless single-select enum_list captures `null`.

**Verdicts:**
- `MATERIALITY` refuted=False (high): The finding survives every materiality gate. (1) Reachable from a conforming peer: `surfaces.dialog` is advertised (DeviceBridge.kt:60), the dialog profile advertises checkbox/switch/enum_list/slider/text_input (NodeSupport.kt:26-28,46-48 — DIALOG_NODE_TYPES includes INPUT_NODE_TYPES), and emacs/ebp.el:1245 `ebp-client-dialog-show` is a real sender. (2) No prior gate rejects it — the opposite: Spe
- `SPEC TEXT` refuted=False (high): Both quotes are verbatim and normative. SPEC.md:1248-1250 reads exactly "At occurrence time, the Companion MUST copy all selected / current values into `event.action.fields` as one logical snapshot before any / dependent state can change." and SPEC.md:2219-2221 independently states "For `dialog.submit`, `fields` MUST be omitted when `capture_fields` is absent or / empty and otherwise MUST contain 
- `CODE TRUTH` refuted=False (high): Reproduced by reading. Renderer.kt:537 is verbatim `fields.put(fieldId, dialog.fields[fieldId] ?: "")`; RenderDialogRoot (Renderer.kt:114) creates the map empty with no seeding walk; a repo-wide grep shows `dialog.fields` is written only at Renderer.kt:94 (RenderCtx.state), which every input node calls solely from its change callback (RenderCheckbox onCheckedChange InputNodes.kt:190-194; RenderSwi

## [P2] [unverified] §14.2 — Builtins are not gated to the target profile's advertised `builtins`: an unadvertised or wrong-context builtin is accepted instead of rejected 1201

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:927  
**SPEC line:** 1294  
**Auditor:** Audit SS18.1 through SS18.3 (dialogs incl. the dialog.show request and

**SPEC quote:**
> `view.switch` is valid only inside a multi-view `app:*` surface and `view` MUST name one of that snapshot's views. `dialog.submit` and `dialog.dismiss` are valid only inside their containing outstanding dialog. Every other builtin is valid only in a target profile that advertises it. An unexpected parameter or invalid context MUST reject the containing document.

**Detail:** validateAction resolves a builtin against the GLOBAL vocabulary only: `row = ACTION_SCHEMA[name] ?: throw ContentInvalid(...)` (SpecValidator.kt:924-928). There is no `advertisedBuiltins` parameter anywhere in SpecValidator — Ctx (lines 70-83) carries only `advertisedTypes`. handleDialogShow (CompanionEngine.kt:1414-1421) passes `advertisedTypes = nodeTypesFromProfiles(config.surfaceProfiles, "dialog")` and nothing else; handleSurfaceUpdate does the same for "app". So the per-target `builtins` array the Companion itself advertises (NodeSupport.kt:56-61: APP_BUILTINS excludes dialog.submit/dismiss, DIALOG_BUILTINS = {dialog.submit, dialog.dismiss} only) is reported in the welcome but never enforced. The renderer then silently swallows the mismatch: onButton (Renderer.kt:530-546) returns unconditionally after the dialog `when` block, so a non-dialog builtin inside a dialog does nothing; executeBuiltin (CompanionEngine.kt:207-240) has no dialog.submit/dismiss branch, so those do nothing on a surface. Both are silent no-ops where §14.2 requires whole-document rejection. Note the parallel notification-side hole was found and fixed (SpecValidator.kt:242-243, commit 3a434bc); the dialog/app-profile hole was not. No test covers it: BuiltinTest.kt only exercises builtins that ARE advertised, and DialogTest.kt's dialog profile happens to advertise exactly what its specs use.

**Failure scenario:** (a) Emacs sends dialog.show {dialog_id:"d", spec:{t:"button",label:"Copy",on_tap:{builtin:"clipboard.copy",text:"secret"}}}. clipboard.copy is NOT in DIALOG_BUILTINS, so §14.2 requires 1201 content-invalid. Instead the Companion accepts the dialog, displays it, and the Copy button is a dead control — the user taps it and nothing is copied, with no diagnostic. (b) Emacs sends surface.update app:main with on_tap {builtin:"dialog.submit"} — an invalid context by the quoted sentence. The Companion returns status:"applied"; at tap time executeBuiltin's `when` matches no branch and the tap is silently discarded.

**Proposed fix:** Thread the target profile's builtins set into Ctx alongside advertisedTypes (handleDialogShow -> "dialog", handleSurfaceUpdate -> the namespace's profile) and, in validateAction's builtin branch, reject with ContentInvalid when the name is absent from that set. Additionally reject dialog.submit/dialog.dismiss whenever the document is not a dialog, and view.switch when the surface is not a multi-view app:* snapshot.

## [P2] [CONFIRMED] §14.2 — Builtin context and parameter validity are never checked: view.switch naming a nonexistent view, or a dialog/unadvertised builtin on the wrong target, is accepted and then silently does nothing

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:927  
**SPEC line:** 1290  
**Auditor:** Audit SS14.1 through SS14.3 (ActionDescriptor shape, the dotted action

**SPEC quote:**
> `view.switch` is valid only inside a multi-view `app:*`
surface and `view` MUST name one of that snapshot's views. `dialog.submit` and
`dialog.dismiss` are valid only inside their containing outstanding dialog.
Every other builtin is valid only in a target profile that advertises it. An
unexpected parameter or invalid context MUST reject the containing document.

**Detail:** validateAction's builtin branch is `row = ACTION_SCHEMA[name] ?: throw ContentInvalid(...)` (SpecValidator.kt:927-928) followed by the generic required/closed-member loops (949-955). That covers "unknown builtin" and "unexpected parameter" but nothing else: the validator has no view list, no dialog flag, and no builtins allowlist. `Ctx` carries `advertisedTypes` for node_types (SpecValidator.kt:77) but there is no equivalent for `surface_profiles.<target>.builtins`, and CompanionEngine only ever passes node types (handleSurfaceUpdate → SurfaceStore.update → validateSurfaceSpec, SurfaceStore.kt:150-153; handleDialogShow at CompanionEngine.kt:1414-1421). Consequently: (a) `{builtin:"view.switch", view:"nope"}` and `view.switch` inside a single-view surface both validate; at tap, executeBuiltin's `surfaces.switchView` returns false (SurfaceStore.kt:96-103) and the branch returns with no diagnostic (CompanionEngine.kt:211). (b) `{builtin:"dialog.submit"}` on an `app:*` surface validates; executeBuiltin has no matching case and falls through (CompanionEngine.kt:237-240). (c) `clipboard.copy`/`share.send`/`trigger.fire` inside a dialog validate even though NodeSupport.DIALOG_BUILTINS is only `{dialog.submit, dialog.dismiss}` (NodeSupport.kt:64); inside a notification body they validate even though the notification profile advertises zero builtins.

**Failure scenario:** Emacs pushes a single-view `app:agenda` with `{t:"button", label:"Week view", on_tap:{builtin:"view.switch", view:"week"}}` (a typo'd or stale view name in a multi-view surface behaves identically). Per §14.2 this MUST be rejected with 1201 so Emacs learns its snapshot is wrong. Instead surface.update returns `{status:"applied"}`, the button renders normally, and every tap is an unreported no-op — the user sees a dead control and Emacs has no signal that anything is broken.

**Proposed fix:** Give `Ctx` two new fields: `advertisedBuiltins: Set<String>?` and `viewNames: Set<String>?` (null on both = allow-all for unit tests/goldens), plus the `isDialog` flag from the previous finding. In validateAction's builtin branch: reject a builtin absent from `advertisedBuiltins`; reject `view.switch` when `viewNames` is null (single-view surface) or when `obj.getString("view")` is not in it; reject `dialog.submit`/`dialog.dismiss` unless `isDialog`. Populate the fields in validateSurfaceSpec from the multi-view `views` keySet and from a builtins set threaded the same way `advertisedTypes` already is — CompanionEngine already has `nodeTypesFromProfiles(config.surfaceProfiles, target)` (used at CompanionEngine.kt:1421), so add the parallel `builtinsFromProfiles`. Tests: view.switch with an unknown view → 1201; view.switch on a single-view surface → 1201; dialog.submit on an app surface → 1201; clipboard.copy in a dialog spec → 1201.

**Verdicts:**
- `SPEC TEXT` refuted=False (high): The quote is verbatim, normative, and in force. SPEC.md:1291-1295 reads exactly: "`view.switch` is valid only inside a multi-view `app:*` surface and `view` MUST name one of that snapshot's views. `dialog.submit` and `dialog.dismiss` are valid only inside their containing outstanding dialog. Every other builtin is valid only in a target profile that advertises it. An unexpected parameter or invali
- `MATERIALITY` refuted=False (high): SPEC.md:1290-1293 makes it explicit: "`view.switch` is valid only inside a multi-view `app:*` surface and `view` MUST name one of that snapshot's views... Every other builtin is valid only in a target profile that advertises it. An unexpected parameter or invalid context MUST reject the containing document." The code has no such check and no data to make it with: SpecValidator.kt:927-928 is `row =
- `CODE TRUTH` refuted=False (high): Reproduced by reading. SpecValidator.kt:924-928 is the entire builtin branch — `row = ACTION_SCHEMA[name] ?: throw ContentInvalid("$path.builtin", "unknown builtin $name")` — and Ctx (SpecValidator.kt:70-83) holds only maxCaptureFields/maxChartPoints/maxCanvasOps/advertisedTypes: no builtins allowlist, no view-name set, no isDialog. validateSurfaceSpec parses `spec.views` (lines 98-111) but never 

## [P2] [CONFIRMED] §14.3 — A Companion-local builtin on a value-producing hook is accepted instead of rejecting the document, and then executes as a builtin

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:923  
**SPEC line:** 1318  
**Auditor:** Audit SS14.1 through SS14.3 (ActionDescriptor shape, the dotted action

**SPEC quote:**
> A builtin on any other value-producing hook
is invalid.

**Detail:** validateAction receives the hook name (`hook` parameter, SpecValidator.kt:879) and uses it only in the remote branch, to look up INJECTED_MEMBERS for the authored-conflict check (lines 915-922). The builtin branch (lines 923-929) ignores `hook` entirely: it checks only that the name is a key of ACTION_SCHEMA, then falls through to the shared required/closed-member loops. So every hook in the §14.3 injection table — on_change, on_submit, on_save, on_enter, on_pick, on_reorder, on_add_row, on_add_col, on_day_tap, on_month_change, on_point_tap, swipe_start.on_trigger, swipe_end.on_trigger — accepts any builtin, in any surface, with no dialog-context exception logic. §16.1 (SPEC.md:1682) makes an "invalid action descriptor" a whole-update 1201, so these documents MUST be rejected. Worse, the accepted descriptor then *runs*: dispatchAction's first line (CompanionEngine.kt:255) routes any `builtin` to executeBuiltin, so the hook's produced value is discarded and a Companion-local control action fires instead.

**Failure scenario:** Emacs pushes `app:settings` containing `{t:"checkbox", id:"agree", label:"I agree", on_change:{builtin:"companion.settings.open"}}`. The surface is accepted (must be 1201). The user ticks the box: RenderCheckbox (InputNodes.kt:190-194) publishes `state.changed {id:"agree", value:true}` and then calls `ctx.action(onChange, true)` → dispatchAction → `descriptor.has("builtin")` → executeBuiltin → hostBuiltinListener("companion.settings.open") → the Companion's settings UI opens on a checkbox flip, and no `event.action` for the change is ever sent. The same shape with `{builtin:"clipboard.copy", text:"..."}` on a `slider.on_change` silently writes the clipboard on every gesture commit.

**Proposed fix:** In SpecValidator.validateAction's builtin branch, reject when `hook` is a key of INJECTED_MEMBERS, with one carve-out: `hook == "on_submit"` and the builtin is `dialog.submit` and the traversal is validating a dialog document. Thread a `isDialog: Boolean` flag onto `Ctx` (set from a new `validateSurfaceSpec(..., isDialog = true)` argument used by CompanionEngine.handleDialogShow at CompanionEngine.kt:1414) so the exception can be scoped exactly as §14.3 words it. While there, enforce §17.4's companion rule that `clear_on_submit: true` is invalid when `on_submit` is a builtin. Tests: builtin on on_change/on_pick/on_reorder → 1201; `dialog.submit` on on_submit inside a dialog → accepted; the same descriptor on an app surface → 1201.

**Verdicts:**
- `SPEC TEXT` refuted=False (high): The quote is verbatim and normative. SPEC.md:1314-1319 (§14.3, normative prose, no MAY/SHOULD hedge): "The injection table applies to remote ActionDescriptors. Every hook listed in the table MUST use a remote descriptor, except that `on_submit` inside a dialog MAY use the `dialog.submit` builtin. That exception performs no implicit value injection; it MUST use the builtin's authored `value` or `ca
- `MATERIALITY` refuted=False (high): SPEC.md:1318 "A builtin on any other value-producing hook is invalid" + SPEC.md:1682 (§16.1 "invalid action descriptor ... MUST reject the entire update with 1201") make this a MUST-reject. SpecValidator.kt:923-929 is the whole builtin branch: `val name = obj.opt("builtin") as? String ...; row = ACTION_SCHEMA[name] ?: throw ContentInvalid(...)` — the `hook` parameter is never consulted, and grep c
- `CODE TRUTH` refuted=False (high): Reproduced by reading. SPEC.md:1316-1318 — "Every hook listed in the table MUST use a remote descriptor, except that `on_submit` inside a dialog MAY use the `dialog.submit` builtin... A builtin on any other value-producing hook is invalid." In SpecValidator.kt, `INJECTED_MEMBERS` is referenced in exactly two places (declaration at :47, use at :915) and the :915 use sits inside `if (hasAction)` — t

## [P2] [CONFIRMED] §14.6 — ebp.el's state.changed reconciliation implements only the reset half of §14.6, and records reset ids before the update is accepted

**Location:** `emacs/ebp.el`:941  
**SPEC line:** 1496  
**Auditor:** Audit SS13.5 and SS13.6 (input state, drafts, draft reconciliation on 

**SPEC quote:**
> Emacs MUST NOT discard a `state.changed` merely because `revision_seen` is
older than its newest pushed revision. It MUST reconcile the reported value
against its newest accepted snapshot using exactly the Section 13.6 rules.
When the ID survives with a compatible value schema and no accepted snapshot
with a revision greater than `revision_seen` named that ID in
`reset_input_ids`, the reported value is the node's live draft and Emacs
SHOULD adopt it. When the ID was reset, removed, or is incompatible under
Section 13.6, the Companion has already erased or reseeded that draft;
Emacs MUST discard the reported value without treating the notification as
an error.

**Detail:** `ebp-client--handle-state-changed` (ebp.el:941-955) applies exactly one of the three discard conditions: `ebp-client--state-reset-p` against the reset history. It never checks 'removed' or 'incompatible under Section 13.6', and it structurally cannot: the ebp-client struct (ebp.el:490-522) retains `revisions`, `input-values` and `reset-history` but no per-surface snapshot or stateful inventory — `ebp-client-surface-update` (ebp.el:1116-1133) treats SPEC as an opaque value it forwards. Per REWRITE-PLAN's own boundary table, "`state.changed` reconciliation, `input_state` merge, draft rules" is an ebp.el endpoint duty (and §24.2 lists "input-state reconciliation" as an Emacs MUST), so this is not deferred application scope. Second defect at the same seam: `ebp-client--record-reset-ids` is called synchronously at ebp.el:1131-1132, immediately after `ebp-client--surface-request` returns the claimed revision and long before the result arrives — so a reset is recorded even when the Companion answers 1201 content-invalid or {status:"stale"} and therefore never cleared the draft. The SPEC's qualifier is 'no ACCEPTED snapshot ... named that ID in reset_input_ids'.

**Failure scenario:** (A) Emacs pushes app:main rev 1 containing text_input id="title". The user types; the Companion sends state.changed {surface:"app:main", revision_seen:1, id:"title", value:"draft"}. Concurrently Emacs pushes rev 2 whose spec no longer contains any node with id "title". The notification is processed after: reset-history is empty for "title", so ebp.el puthashes ("app:main" . "title") → "draft" into input-values and fires state-changed-functions. But the Companion has already erased that draft (SurfaceStore.reconcileDrafts, node==null branch), and §14.6 requires Emacs to discard it. Emacs now holds a phantom value that `ebp-client-input-value` will hand back the next time the application re-introduces id "title", re-seeding a field with text the Companion has no record of. (B) Emacs pushes rev 5 with reset_input_ids ["title"] but a malformed node in the spec; the Companion returns 1201 and leaves both the snapshot and the draft untouched. ebp.el has already pushed (5 . ("title")) into reset-history, so the Companion's subsequent legitimate state.changed with revision_seen 4 for "title" is discarded with a "discarded" message, permanently losing the user's live draft on the Emacs side while the Companion keeps it.

**Proposed fix:** Retain, per surface, the stateful inventory of the last ACCEPTED snapshot (id → node type plus the §13.6 schema-relevant members: password, single_line, multi_select, allow_add, options, values/min/max, publish_state/document) — ebp.el can derive it from the spec it is already handed at push time — and run the full §13.6 compatibility matrix in `ebp-client--handle-state-changed`, discarding when the id is absent, retyped, or schema-incompatible. Move the `ebp-client--record-reset-ids` call into the `ebp-client--surface-request` result callback, conditional on (equal status "applied"), and prune reset-history entries below the absorbed floor so it does not grow without bound.

**Verdicts:**
- `SPEC TEXT` refuted=False (high): The quote is verbatim at SPEC.md:1496-1505, a normative bullet in §14.6, not a note or example. The clause the finding says is unimplemented is MUST-level and addressed to Emacs: "When the ID was reset, removed, or is incompatible under Section 13.6, the Companion has already erased or reseeded that draft; Emacs MUST discard the reported value" (SPEC.md:1502-1505) — only the adopt half is SHOULD. 
- `CODE TRUTH` refuted=False (high): Both defects reproduce by reading, and nothing handles them elsewhere.

(1) `ebp-client--handle-state-changed` (emacs/ebp.el:941-955) branches on exactly one predicate — `ebp-client--state-reset-p` (ebp.el:933-939), which only scans `reset-history` — then unconditionally `puthash`es the reported value into `input-values` and fires the hook. No removal check, no §13.6 schema check. It structurally 

## [P2] [unverified] §15.1 — A trigger occurrence refused by the durable queue (queue-full or storage failure) is discarded with no user-visible diagnostic

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/TriggerFiringService.kt`:183  
**SPEC line:** 1566  
**Auditor:** Audit SS15 (durable queue and replay) against DurableQueue.kt, QueueSt

**SPEC quote:**
> If storage fails, the Companion MUST NOT claim that the interaction was queued.
It MUST notify the user of the failure. If queue capacity is exhausted, it MUST
reject admission with a visible diagnostic equivalent to `1601 queue-full`.

**Detail:** Both other admission entry points honour the MUST: `CompanionEngine.dispatchAction` maps `AdmitResult.QueueFull` to a 1601/`queue-full` callback error (CompanionEngine.kt:318-322) and `StorageFailed` to -32603 (lines 323-327), which `DeviceBridge.action`/`actionInjecting`/`actionWithFields` surface through `onQueueProblem` (DeviceBridge.kt:155, 166, 177 → MainActivity.kt:46); `dispatchContextless` produces the same two errors on its callback (ContextlessEvents.kt:72-77).

`TriggerFiringService.admit` is the exception: its `when (val r = queue.admit(...))` collapses both failure results into `else -> Unit` at TriggerFiringService.kt:183 with the comment "durable transaction failed: no throttle, no on_fire". Suppressing the throttle and `on_fire` is right, but the occurrence then vanishes with no notification — even though the service already holds a `notifyListener` (used by `executeOnFire`, TriggerFiringService.kt:202, wired to `Notifications.postTrigger` in CompanionStores.kt:117) that could raise exactly the required visible diagnostic. The `drop`-policy branch at TriggerFiringService.kt:190 swallows commit failures the same way, but §15.1's notify MUST is scoped to durable admission, so line 183 is the violation.

**Failure scenario:** Device is disconnected from Emacs for a day with `max_queued_events = 256` (CompanionStores.kt:67). Queued surface actions plus a `policy:"queue"` `time.every_s` trigger fill the queue; `DurableQueue.admit` then returns `QueueFull` at DurableQueue.kt:137-138 for every subsequent firing. Each firing is silently dropped at TriggerFiringService.kt:183 — no notification, no log, and (correctly) no throttle advance, so the trigger keeps re-firing and keeps being silently lost. The user has no way to learn that the device stopped recording their trigger occurrences; the only visible signal is that the events simply never arrive after reconnect.

**Proposed fix:** Replace `else -> Unit` at TriggerFiringService.kt:183 with an explicit two-arm `when` that routes `AdmitResult.QueueFull` and `AdmitResult.StorageFailed` to a new `admissionProblemListener: ((Int, String) -> Unit)?` (invoked post-lock via the existing `pending` deferral list so it never runs under the service monitor), and wire it in `CompanionStores.firing` to `Notifications.postTrigger`-style host notification with the 1601 `queue-full` / internal-error text — mirroring what `DeviceBridge.onQueueProblem` already does for surface actions.

## [P2] [unverified] §15.1 / §15.2 — DurableQueue has no pairing dimension: queue_seq, the clock high-water mark, dedupe compaction and replay head-selection are global across all configured pairings

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/DurableQueue.kt`:33  
**SPEC line:** 1556  
**Auditor:** Audit SS15 (durable queue and replay) against DurableQueue.kt, QueueSt

**SPEC quote:**
> expiration time, and a per-pairing `queue_seq`. `queue_seq` MUST be assigned
from a durable strictly increasing counter and MUST define FIFO order
independently of wall-clock changes. […] The effective wall clock is the greater of the
current wall clock and a durably stored per-pairing high-water mark. […] the Companion MUST atomically
remove every older queued, non-in-flight event with the same key and pairing
identity.

**Detail:** `CompanionConfig.pairings` is a `Map<String, ByteArray>` (CompanionEngine.kt:16) and `handleAuth` selects the token by `pendingPairingId` (CompanionEngine.kt:1519), so the reference wire library explicitly supports N pairings — §9.1 calls the pairing ID the selector for "the correct token and persistent state partition", and requires revocation to erase that identity's "queued payloads".

`DurableQueue` (DurableQueue.kt:33-59) carries no identity at all: one `records` list, one `nextSeq`, one `highWater`, one `QueueStore` file (`CompanionStores.queue`, CompanionStores.kt:63-68 builds exactly one `FileQueueStore(ebp-queue.json)` for the whole process). Consequences, each a distinct MUST miss:
• `admit` (DurableQueue.kt:134) draws `queue_seq` from the single global `nextSeq`, so FIFO order interleaves pairings.
• The dedupe filter at DurableQueue.kt:128-132 matches on the `dedupe` string alone, with no identity term.
• `highWater` is one global mark, not per-pairing.
• `beginDelivery` (DurableQueue.kt:84) returns the global minimum-`queue_seq` record, so a session authenticated as pairing A replays pairing B's events.
• `buildWelcome` reports `queue.count()` for `queued_events` (CompanionEngine.kt:1550), which §10.2 line 821 defines as the count "for this pairing identity".
Note `TriggerStore` IS partitioned by identity (`store.registration(identity, id)`, `TriggerStore.identities()`), and `admit` even stamps `trigger_identity` into the record (DurableQueue.kt:126) — but only for §21.2 throttle recovery; nothing reads it for scoping. The shipped app configures a single pairing (DeviceBridge.kt:57-59), so this is latent there, but the library under audit is the reference and its API admits the multi-pairing case with no guard or documented restriction.

**Failure scenario:** `CompanionConfig(pairings = mapOf(A to tokenA, B to tokenB))`. Pairing B registers `triggers.set` with a `policy:"queue"` `sms.received` trigger; it fires while B is disconnected and is admitted at `queue_seq = 7`. Pairing A's Emacs then connects: `buildWelcome` reports `queued_events: 1` (B's record) and A's §10.3 `queue.replay` runs `beginDelivery(barrier)`, which selects seq 7 and sends B's `trigger.fired` — including the SMS body in `args.data` — to A's Emacs as an `event.action`. Separately, if A and B both author `dedupe: "agenda-sync"`, B's admission deletes A's still-queued record at DurableQueue.kt:129-132, losing A's occurrence entirely.

**Proposed fix:** Add a required `pairingId: String` parameter to `DurableQueue.admit` and store it in the record; key `nextSeq`, `highWater`, and `pendingExpired` by pairing in `QueueSnapshot` (e.g. `Map<String, Long> nextSeq` / `clockHighWater`); add the identity term to the dedupe filter (`it.optString("pairing") == pairingId &&`) and to `sweepExpired`'s effective-now; give `beginDelivery`, `count`, `head`, and `boundarySeq` a `pairingId` argument so the pump and `queued_events` only ever see the authenticated identity's partition. Thread `pendingPairingId` from `CompanionEngine` into `dispatchAction`/`dispatchContextless`, and use `reg.identity` (already available) in `TriggerFiringService.admit`. Until that lands, `CompanionConfig` should `require(pairings.size <= 1)` in `checkLimits` so the unsupported case fails loudly instead of cross-delivering.

## [P2] [unverified] §15.3 — `ebp-client--force-replay-retry` is permanently disarmed after the first retry timer ever fires, so a `1500 event-retry` never restarts the Companion's paused pump

**Location:** `emacs/ebp.el`:743  
**SPEC line:** None  
**Auditor:** Audit emacs/ebp.el as a whole against every SPEC duty assigned to "a c

**SPEC quote:**
> Emacs SHOULD call `queue.replay`
with bounded backoff after it returns a transient error for an automatically
delivered durable event.

**Detail:** `ebp-client--schedule-replay-retry` assigns the timer object into the `replay-retry-timer` slot (ebp.el:721-722) but the timer's own lambda (ebp.el:724-737) never clears that slot, and neither does the recursive re-schedule. `ebp-client--force-replay-retry` (ebp.el:739-751) is guarded by `(unless (ebp-client-replay-retry-timer client) …)`. A fired one-shot timer is removed from `timer-list` but the Lisp object remains in the slot and is non-nil forever. Therefore, once any retry cycle has run, the guard is permanently false and `ebp-client--force-replay-retry` becomes a no-op. This matters because it is the ONLY caller that unpauses the pump after a 1500: `ebp-client--handle-event-action` calls it immediately before returning `1500 event-retry` (ebp.el:912-914), and §15.3 states "A permanent result deletes the head and advances the pump; a JSON-RPC error retains the head and pauses it. Admission of a later event MUST NOT clear that pause or bypass the head." The existing test `ebp-test-replay-retry-until-drained` (test/ebp-wire-test.el:758) asserts exactly two `queue.replay` calls and never combines a drained retry cycle with a later commit failure, so the branch is uncovered.

**Failure scenario:** 1) Session reaches READY with `remaining: 2`; `ebp-client--schedule-replay-retry` sets `replay-retry-timer` to T1. 2) T1 fires, `queue.replay` returns `remaining: 0`; the re-schedule call finds `remaining` zero and creates no new timer, but the slot still holds the fired T1. 3) Later, an `event.action` arrives, the application handler returns `accepted`, but `ebp-client--receipt-commit` fails (transient disk-full, or SQLITE_BUSY from a concurrent handle). `ebp-client--force-replay-retry` sees non-nil T1 and returns without scheduling; Emacs answers `1500 event-retry`. The Companion retains the head and pauses its single-file pump. No further `queue.replay` is ever sent for the rest of the session, so that event and every durable event admitted behind it are stranded until the next reconnect — including `wake`-policy trigger events the module exists to deliver.

**Proposed fix:** Clear the slot at the top of the timer's lambda: `(setf (ebp-client-replay-retry-timer client) nil)` as the first form inside the `run-at-time` closure, and also set it to nil in `ebp-client--schedule-replay-retry` when the `remaining > 0` guard fails (so a drained backlog leaves the slot empty). Optionally `cancel-timer` any existing timer before overwriting the slot. Add an ERT that drains a backlog, then delivers an event whose receipt commit fails, and asserts a third `queue.replay` reaches the server.

## [P2] [unverified] §15.3 — ebp.el never clears `replay-retry-timer`, so `ebp-client--force-replay-retry` is a permanent no-op after the first retry cycle and the Companion's paused pump is never resumed

**Location:** `emacs/ebp.el`:743  
**SPEC line:** 1604  
**Auditor:** Audit SS15 (durable queue and replay) against DurableQueue.kt, QueueSt

**SPEC quote:**
> Emacs SHOULD call `queue.replay`
with bounded backoff after it returns a transient error for an automatically
delivered durable event.

**Detail:** `ebp-client--schedule-replay-retry` assigns the timer at ebp.el:721 (`(setf (ebp-client-replay-retry-timer client) (run-at-time …))`) and the timer's own closure (ebp.el:724-737) never sets that slot back to nil when it fires; the slot is only ever cleared by `ebp-client-close` (ebp.el:573-574). `ebp-client--force-replay-retry` — the ONLY path that restarts replay after Emacs answers `1500 event-retry` for an auto-delivered durable event — is gated on `(unless (ebp-client-replay-retry-timer client) …)` at ebp.el:743. Once any retry has ever been scheduled in a connection, that slot holds an expired timer object forever, so every later `force-replay-retry` silently does nothing.

On the Companion side this is unrecoverable within the session: `onPumpResult`'s error branch sets `pumpPaused = true` (CompanionEngine.kt:513) and the only writer of `pumpPaused = false` is `handleQueueReplay` (CompanionEngine.kt:466). `pumpAdvance` returns immediately while paused (CompanionEngine.kt:478-481), and admission deliberately does not clear the pause (§15.3: "Admission of a later event MUST NOT clear that pause or bypass the head"). So no further durable event is ever delivered until the transport drops and Emacs reconnects.

**Failure scenario:** One READY connection, `:receipt-file` on a filesystem that intermittently fails writes. (1) Durable event E1 auto-delivers; `ebp-client--receipt-commit` fails; ebp.el:912 calls `force-replay-retry`; the slot is nil so it schedules timer T1 and answers `1500 event-retry`; the Companion pauses the pump. (2) T1 fires, sends `queue.replay`; E1 succeeds this time; the summary has `remaining: 0`, so `schedule-replay-retry` creates no new timer — but the slot still holds the fired T1. (3) Later, durable event E2 auto-delivers and its receipt commit fails again; ebp.el:912 calls `force-replay-retry`, the `unless` at ebp.el:743 sees non-nil T1 and returns without doing anything; Emacs answers `1500` and never sends another `queue.replay`. The Companion's pump stays `pumpPaused` with E2 and every later durable event retained forever — a wedged backlog for the remainder of the connection, with no diagnostic on either endpoint.

**Proposed fix:** Clear the slot from inside the timer closure before issuing the request — i.e. as the first form of the `(lambda () …)` at ebp.el:724 add `(setf (ebp-client-replay-retry-timer client) nil)`. (Alternatively change the ebp.el:743 gate to test `(and timer (timer--triggered timer))`, but nilling on fire is the robust fix and also stops `close` from cancelling a dead timer.)

## [P2] [unverified] §16.1 — checkbox and switch share one saved-state key that omits the node type, so a checkbox→switch id reuse restores the old draft instead of clearing it

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/InputNodes.kt`:185  
**SPEC line:** None  
**Auditor:** Audit SS16 (UI document model) — SS16.1 node identity and the identity

**SPEC quote:**
> The discriminator `t` is part of the identity: reusing a key
or ID with a different node type creates a new identity and MUST clear retained
presentation state.  ...  their identity consists of surface, ID, node
type, and value schema under Section 13.6.

**Detail:** `identityPath` (Attributes.kt:77-85) includes the `t` discriminator only in its tree-path branch; the `key` and `id` branches emit `"$parentPath/k:$key"` / `"$parentPath/id:$id"` with no type. The same omission is repeated in the explicit `rememberSaveable` keys: RenderCheckbox uses `key = "in:${ctx.surface}:$id"` (InputNodes.kt:185) and RenderSwitch uses the *identical* string (InputNodes.kt:205). Because `rememberSaveable`'s explicit key is the SaveableStateRegistry key that survives activity save/restore, a checkbox's saved boolean is restored into a switch with the same id. text_input ("ti:") vs editor ("ed:") happen to differ only by an ad-hoc prefix, so the invariant is accidental rather than enforced. §16.1 enumerates node type as part of a draft's identity precisely so this cannot happen, and §13.6 lists "the same ID is reused for a different node type" as a MUST-clear condition — which the wire store honors (SurfaceStore.reconcileDrafts) while the Compose mirror does not.

**Failure scenario:** app:main rev 1 contains `{"t":"checkbox","id":"flag","checked":false}`; the user checks it (local true, wire draft true). The user backgrounds the app and Android destroys the activity, persisting `in:app:main:flag = true` in saved-instance-state. While destroyed, Emacs pushes rev 2 with `{"t":"switch","id":"flag","checked":false}`; SurfaceStore.reconcileDrafts erases the draft (node type changed). The user returns, the activity is recreated, and `rememberSaveable(..., key = "in:app:main:flag")` in RenderSwitch restores `true`. The switch renders ON although the authored value is `false` and no draft exists — retained presentation state that §16.1 says MUST have been cleared, and the value the user sees no longer matches the `input_state` the Companion will report.

**Proposed fix:** Put the node type in every local-state key: `key = "in:${ctx.surface}:$t:$id"` (and likewise `"ti:"`/`"ed:"` → a single `"input:${surface}:${t}:${id}"` scheme), and add `t` to the key/id branches of `identityPath` (`"$parentPath/k:$key:$t"`, `"$parentPath/id:$id:$t"`) so a type change always mints a new identity. Cover it with a JVM test over `identityPath` asserting that the same key with two different `t` values yields two different paths.

## [P2] [unverified] §16.1 (input-draft exception) / §13.6 — Stateful input nodes never re-seed from a newly authored value: the renderer's local state is created once per (surface, id) and ignores every later snapshot's `value`/`checked`

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt`:236  
**SPEC line:** None  
**Auditor:** Audit SS16 (UI document model) — SS16.1 node identity and the identity

**SPEC quote:**
> Input drafts are the deliberate exception because
their wire address is a node ID: their identity consists of surface, ID, node
type, and value schema under Section 13.6.  ...  Anything else is incompatible. The Companion MUST erase an incompatible draft
and seed the node from the newly authored value or that node's default, without
emitting `state.changed` or a user action.

**Detail:** Every stateful renderer creates its local value with the authored value inside a `remember`/`rememberSaveable` calculation whose only inputs are the surface and the node id: text_input `rememberSaveable(ctx.surface, id, key = "ti:${ctx.surface}:$id") { mutableStateOf(node.optString("value")) }` (Renderer.kt:236-238), editor (Renderer.kt:318-321), checkbox (InputNodes.kt:185), switch (InputNodes.kt:205), enum_list (InputNodes.kt:251-253), slider (InputNodes.kt:363, 379). The calculation lambda runs exactly once for the lifetime of that (surface,id) pair, so a later accepted snapshot that authors a different value never reaches the widget. The wire side does reconcile correctly — `SurfaceStore.reconcileDrafts` (SurfaceStore.kt:262-279) clears an acknowledged or incompatible draft and `valueFor()` (SurfaceStore.kt:106-108) then falls back to the authored value — so after reconciliation the Companion's own `input_state` (reported in the next §10.2 welcome) and the pixels on screen disagree. There is no `LaunchedEffect` on the authored value anywhere in the render package to close the gap (grep: the only value-driven effect is enum_list's option-pruning at InputNodes.kt:259).

**Failure scenario:** app:main rev 1: `{"t":"slider","id":"s","min":0,"max":10,"value":5}`. The user drags to 8 → draft 8. rev 2: `{"t":"slider","id":"s","min":0,"max":3,"value":1}`. §13.6 makes 8 incompatible (outside the new continuous range), so the wire store erases the draft and the node must be seeded from the newly authored 1. Observed: `pos` is still 8.0 (InputNodes.kt:379-381 never re-runs); the Slider is drawn with value 8 against valueRange 0f..3f, so the thumb pins at the far right instead of at 1, and the user's next drag-finish publishes a value derived from that wrong position. The simpler case is just as broken: `{"t":"text_input","id":"q","value":"alpha"}` followed by `{"t":"text_input","id":"q","value":"beta"}` (user never typed) leaves the field showing "alpha".

**Proposed fix:** Drive the widget from the authored value plus an explicit dirty flag rather than from a one-shot seed. E.g. keep `var draft by rememberSaveable(...) { mutableStateOf<T?>(null) }` and render `draft ?: authoredValue`; clear `draft` in a `LaunchedEffect(authoredValue)` whenever the new authored value equals the draft (acknowledgement) or is incompatible under the §13.6 compatibility table. Alternatively have the engine rewrite the accepted spec's stateful nodes from `SurfaceStore.valueFor()` before handing it to `onSurfaceChanged`, and key the composables on that value so the wire store stays the single source of truth.

## [P2] [unverified] §16.5 — The §16.5 universal attribute `align_self` is not implemented anywhere in the renderer, yet it is advertised in the contract vocabulary and marked done in the parity matrix

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Attributes.kt`:110  
**SPEC line:** None  
**Auditor:** Audit SS16 (UI document model) — SS16.1 node identity and the identity

**SPEC quote:**
> | `align_self` | `start` \| `center` \| `end` \| `stretch` | — | Override parent cross-axis alignment |

**Detail:** `Modifier.universal(node)` (Attributes.kt:110-160) applies padding/pad, width/height, min/max bounds, fill_fraction, aspect_ratio, corner, clip, bg, border and alpha. Its header comment claims "`weight` and `align_self` need the parent Row/Column scope and are applied by the container cases" (Attributes.kt:5-6), but only `weight` actually is (Renderer.kt:196-217 `weightOf` → `Modifier.weight`). A repo-wide grep for `align_self` returns exactly four hits: SPEC.md:1756, ebp/contract.json (the `universal_node_attributes` list and `enums.align_self`), Vocabulary.kt:15 (`UNIVERSAL_NODE_ATTRIBUTES`), and the Attributes.kt comment above — no `RowScope.align` / `ColumnScope.align` / `Alignment.Start|CenterHorizontally|End` / `Modifier.fillMaxHeight()` call keyed on it in any renderer. §16.4 defines Render as preserving "the declared semantic structure" and permits only appearance/idiom substitution, not dropping a declared layout override. Nothing detects this: `NodeSupportPinTest` pins node *types* only, and `test/smoke-attrs.el` contains no `align_self` (grep). `docs/W9-feature-parity.md:31` nevertheless records "§16.5 universal attributes (key/padding/sizes/fill/aspect/weight/bg/corner/border/alpha/clip/align_self) | W9-b | ✅".

**Failure scenario:** Emacs pushes `{"t":"row","align":"top","children":[{"t":"surface","bg":"primary_container","align_self":"stretch","children":[{"t":"text","text":"|"}]},{"t":"column","children":[ ...tall content... ]}]}` — a full-height accent rail beside a tall column. The row's own `align:"top"` governs both children; `align_self:"stretch"` is silently discarded, so the rail is drawn at its intrinsic one-line height instead of the row's height. Emacs has no way to detect the loss: `align_self` is a universal attribute with no per-profile advertisement, so the sender-side gate of §16.2 cannot be applied to it.

**Proposed fix:** Read `align_self` in the scoped child helpers (Renderer.kt:200-217) where the Row/Column scope is available: in `RowScope.RenderRowChildren` map start/center/end → `Modifier.align(Alignment.Top|CenterVertically|Bottom)` and stretch → `Modifier.fillMaxHeight()`; in `ColumnScope.RenderColumnChildren` map to `Alignment.Start|CenterHorizontally|End` and `Modifier.fillMaxWidth()`. Add the attribute to `test/smoke-attrs.el` and extend NodeSupportPinTest (or a new pin test) to source-scan `Attributes.kt` + the child helpers against `Vocabulary.UNIVERSAL_NODE_ATTRIBUTES` so an unimplemented universal attribute cannot ship again.

## [P2] [unverified] §16.6 — The theme roles `tertiary_container` and `on_tertiary_container` are absent from the color resolver, so a standard registry role resolves to the unknown-role fallback and renders content invisible

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/ColorModel.kt`:54  
**SPEC line:** None  
**Auditor:** Audit SS16 (UI document model) — SS16.1 node identity and the identity

**SPEC quote:**
> A Color is either a theme-role identifier or one of `#rgb`, `#rgba`,
`#rrggbb`, or `#rrggbbaa`. Hex digits are case-insensitive. Theme-role names are
resolved from the active theme. A Companion receiving an unknown role MUST use
a legible platform fallback and MUST NOT make content transparent.

**Detail:** `resolveColorIn`'s `when (spec)` (ColorModel.kt:54-83) maps primary/secondary/error containers and their on-colors but omits `tertiary_container` and `on_tertiary_container`; both fall through to `else -> scheme.onSurface`, the branch reserved for *unknown* roles. Both names are standard: §18.4 line 2331 lists "`primary`, `on_primary`, `primary_container`, `on_primary_container`, parallel `secondary`, `tertiary`, and `error` roles", and `ebp/contract.json` `theme_roles` enumerates `tertiary_container` and `on_tertiary_container` explicitly. The theme builder itself accepts them — `buildColorScheme` overlays `tertiaryContainer`/`onTertiaryContainer` from a pushed palette (ThemeModel.kt:83-84) — so the Companion accepts the role on `theme.set` and then cannot resolve it on a node. No test covers the registry: ThemeModelTest only exercises primary/surface/success/warning.

**Failure scenario:** Emacs sends `theme.set {"colors":{"tertiary_container":"#e8def8","on_tertiary_container":"#1d192b"}}` (accepted, scheme.tertiaryContainer = #E8DEF8), then a surface containing `{"t":"surface","color":"tertiary_container","children":[{"t":"text","text":"Tag","color":"on_tertiary_container"}]}`. `RenderSurfaceNode` (LayoutNodes.kt:205) and `RenderText` (ContentNodes.kt:156) both call `resolveColor`, both get `scheme.onSurface`, so the chip background and its label are painted the *same* color: the label is invisible against its own container — the exact illegibility §16.6's fallback rule exists to prevent — while the correctly-pushed palette entry goes unused.

**Proposed fix:** Add `"tertiary_container" -> scheme.tertiaryContainer` and `"on_tertiary_container" -> scheme.onTertiaryContainer` to the `when` in ColorModel.kt, and add a JVM test that iterates every name in `contract.json`'s `theme_roles` and asserts `resolveColorIn(scheme, role, extended) != scheme.onSurface` (or, more precisely, that it does not take the unknown-role branch) so a future registry addition cannot silently degrade.

## [P2] [unverified] §16.6 — `success` and `warning` theme roles are dropped in the rich_text/table-cell span builder, chart series, canvas ops and menu items, which call `resolveColorIn` without the ExtendedColors holder

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/ContentNodes.kt`:215  
**SPEC line:** None  
**Auditor:** Audit SS16 (UI document model) — SS16.1 node identity and the identity

**SPEC quote:**
> Theme-role names are
resolved from the active theme. A Companion receiving an unknown role MUST use
a legible platform fallback and MUST NOT make content transparent.

**Detail:** `success`/`warning` (and their derived on-colors) have no Material slot, so ColorModel resolves them only from the optional `extended: ExtendedColors?` argument (ColorModel.kt:48-53); when it is null they fall through to `else -> scheme.onSurface`, the unknown-role branch (ColorModel.kt:79-82 documents this as intentional). Four call sites omit the argument even though all four are inside @Composable functions where `LocalExtendedColors.current` is available: `RenderRichText` → `buildSpanString(resolve = { resolveColorIn(scheme, it) })` (ContentNodes.kt:215, also the shared span path for §17.3 table cells), the chart series colors (VisualizationNodes.kt:100), the canvas op stroke/fill colors (VisualizationNodes.kt:192, 202) and the menu item colors (LayoutNodes.kt:589). §18.4 line 2333 lists `success` and `warning` as standard roles and `contract.json` `theme_roles` includes them, so they are not unknown roles and must resolve from the active theme.

**Failure scenario:** With the default (or any) theme, Emacs pushes `{"t":"rich_text","spans":[{"text":" DONE ","bg":"success","color":"on_success"}]}` — the standard done-badge idiom. `buildSpanString` resolves `bg` → `scheme.onSurface` (near-black in the light scheme) and `color` → `scheme.onSurface` as well, so the span is painted black text on a black background and the word DONE is unreadable. The same push inside a `text` node (`RenderText`, ContentNodes.kt:156, which uses the composable `resolveColor`) renders correctly green — so the same authored color behaves differently depending on which node carries it.

**Proposed fix:** Capture the extended holder alongside the scheme at each call site and pass it through: in `RenderRichText`/`RenderTable`/`RenderMenu`/`RenderChart`/`RenderCanvas` read `val ext = LocalExtendedColors.current` and use `resolveColorIn(scheme, it, ext)`. Better, delete the two-argument convenience overload so the `extended` parameter cannot be omitted by accident, and add a test asserting `resolveColorIn(scheme, "success", ext) != scheme.onSurface` for the span path.

## [P2] [unverified] §16.6 (with §18.4 role list) — Standard theme roles `tertiary_container` / `on_tertiary_container` are unresolvable — both collapse to `onSurface`, rendering bg+fg pairs invisible

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/ColorModel.kt`:64  
**SPEC line:** 1767  
**Auditor:** Audit SS18.4 (theme.set, color roles, dark tri-state/follow-system fro

**SPEC quote:**
> A Color is either a theme-role identifier or one of `#rgb`, `#rgba`, `#rrggbb`, or `#rrggbbaa`. Hex digits are case-insensitive. Theme-role names are resolved from the active theme. A Companion receiving an unknown role MUST use a legible platform fallback and MUST NOT make content transparent.

**Detail:** `resolveColorIn` (ColorModel.kt:43-84) is the single §16.6 Color resolver for every `color`/`bg`/`border.color` member (call sites: Attributes.kt:149 universal `bg`, Attributes.kt:154 `border.color`, ContentNodes.kt:156 `text.color`, :223 `icon.color`, :248 `badge.color`, :215 RichSpan color, LayoutNodes.kt:205/:296, VisualizationNodes.kt:100/:192/:202/:354). Its `when` block maps 22 role names but omits `tertiary_container` and `on_tertiary_container`, which are both in `ebp/contract.json` `theme_roles` and in §18.4's "parallel `secondary`, `tertiary`, and `error` roles". Both therefore fall to `else -> scheme.onSurface` (ColorModel.kt:82). This is not merely a missing tone: `buildColorScheme` (ThemeModel.kt:83-84) correctly overlays the pushed `tertiary_container`/`on_tertiary_container` into the ColorScheme, so the value exists in the active theme and is simply unreachable by name. No upstream gate hides this — SpecValidator.kt contains no `color` validation at all (grep for `color` returns nothing), so the node reaches the renderer verbatim.

**Failure scenario:** Emacs pushes `theme.set {"colors":{"tertiary_container":"#FFD8E4","on_tertiary_container":"#31111D"}}`, then a surface containing `{"t":"card","bg":"tertiary_container","children":[{"t":"text","text":"Due today","color":"on_tertiary_container"}]}`. Attributes.kt:149 resolves `bg` -> onSurface (#1D1B20 on the light scheme) and ContentNodes.kt:156 resolves `color` -> onSurface (#1D1B20). The label is drawn near-black on a near-black card: contrast 1.0:1, content invisible. The same pair authored with `primary_container`/`on_primary_container` renders correctly, so the failure is silent and role-specific.

**Proposed fix:** Add the two missing rows to the `when` in ColorModel.kt after line 64: `"tertiary_container" -> scheme.tertiaryContainer` and `"on_tertiary_container" -> scheme.onTertiaryContainer`. Then add a pin test that iterates `contract.json` `theme_roles` and asserts `resolveColorIn(lightColorScheme(), role)` differs from the `else` fallback for every role except the ExtendedColors pair, so future contract additions fail the build rather than degrade silently.

## [P2] [unverified] §17.1 — Required members are checked for presence but never for type, so the renderer coerces non-string required members

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:405  
**SPEC line:** 1796  
**Auditor:** Audit SS17.1 through SS17.3 (the node-type vocabulary preamble, conten

**SPEC quote:**
> These definitions are cumulative and MUST be projected together into `contract.json`; a receiver MUST NOT apply type coercion omitted by them.

**Detail:** `validateNode`'s generic required-member loop is presence-only: `for (req in row.required) if (!node.has(req)) throw ContentInvalid(path, "$t missing required $req")` (SpecValidator.kt:404-406). Type enforcement exists only in the hand-written `when (t)` arms, which cover text_input.value, rich_text.spans, slider, enum_list.options, tabs, table, chart, canvas, month_grid and image.url — but not `text.text`, `icon.name`, `section_header.title`, `badge.label`, `button.label`, `chip.label`, `assist_chip.label`, `icon_button.icon`, or `collapsible.header`. §17's preamble (line 1774: "Every listed required member MUST be present and have the listed type") plus §16.1's "invalid required field ... MUST reject the entire update with `1201 content-invalid`" make this a rejection duty. Notably `contract.json` already carries the machine-readable `field_types` map (`"text":"string"`, `"title":"string"`, `"name":"identifier"`, …) that would drive it, but `grep -rn field_types` over the whole tree returns only contract.json — neither `tools/gen-vocabulary.py`'s output (Vocabulary.kt) nor SpecValidator projects it, so the §17.1 "MUST be projected together into contract.json" vocabulary is present but unused.

**Failure scenario:** Emacs pushes `{"t":"section_header","title":{"secret":"internal"}}`. Validation passes (the key is present). `RenderSectionHeader` (ContentNodes.kt:286) calls `node.optString("title")`, which org.json coerces via `String.valueOf(object)` to the literal text `{"secret":"internal"}` — the receiver applied exactly the type coercion §17.1 forbids, and rendered raw JSON as a section heading instead of rejecting the surface with `1201`. The same coercion turns `{"t":"text","text":42}` into the string "42" and `{"t":"badge","label":true}` into "true".

**Proposed fix:** Generate a `FIELD_TYPES` map into Vocabulary.kt from `contract.json.field_types` and, in the generic required-member loop, assert each required member against its declared type (string / identifier / node / node-array / number / boolean) before the per-type `when` runs. Keep the per-type arms for the rules the field-type map cannot express.

## [P2] [unverified] §17.3 / §16.4 — `lazy_column` and `reorderable_list` force `fillMaxSize()`, silently swallowing every following sibling and crashing under an unbounded-height parent

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/LayoutNodes.kt`:247  
**SPEC line:** None  
**Auditor:** Audit SS17.4 through SS17.6 (layout nodes, the scaffold and its slots,

**SPEC quote:**
> “Render” means preserve the declared semantic structure, content, enabled state, interaction hooks, and accessibility meaning. It does not require pixel identity among toolkits or platforms.

**Detail:** RenderLazyColumn measures with `modifier = m.fillMaxSize()` (LayoutNodes.kt:247) and RenderReorderableList does the same (LayoutNodes.kt:640). Neither §17.3 row (`lazy_column | children | spacing, content_padding`; `reorderable_list | items | on_reorder`) declares any sizing behaviour, and §16.5 gives sizing to the universal attributes (`height`, `weight`, `fill_fraction`) that `m` has already applied. Compose's Column measures non-weighted children in order against the REMAINING main-axis space, so a `fillMaxSize` child consumes all of it and every later sibling is measured with maxHeight = 0. When the parent's height is unbounded — a `column` with `scroll: true`, which §17.3 explicitly permits — the lazy list is measured with an infinite maximum height and Compose throws ("Vertically scrollable component was measured with an infinity maximum height constraints"), taking down the composition and the whole surface.

**Failure scenario:** (a) `{t:column, children:[{t:lazy_column, children:[…50 rows…]}, {t:button, label:"Load more", on_tap:{…}}]}` — the button is measured at height 0 and is invisible and untappable; its declared content and interaction hook are lost. (b) `{t:column, scroll:true, children:[{t:lazy_column, children:[…]}]}` — IllegalStateException during measure, the surface renders nothing and the Companion UI crashes, from a document the validator accepted.

**Proposed fix:** Drop the unconditional `fillMaxSize()`: use `m.fillMaxWidth()` and let the §16.5 universal attributes (`height`, `weight`, `fill_fraction`) or the parent's constraints bound the height, e.g. `m.fillMaxWidth().then(if (node.has("height") || node.has("weight")) Modifier else Modifier.heightIn(max = …))`, and guard against an unbounded parent (e.g. wrap in a `BoxWithConstraints`/`heightIn` so an infinite maxHeight can never reach LazyColumn).

## [P2] [unverified] §17.4 — The value cleared by clear_on_submit is never published, so the retained draft and welcome input_state keep the pre-clear text

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt`:260  
**SPEC line:** 2003  
**Auditor:** Audit SS17.1 through SS17.3 (the node-type vocabulary preamble, conten

**SPEC quote:**
> After clearing, it MUST retain focus where the platform permits and MUST update its latest input-state value. While `READY`, it MUST send the cleared value in `state.changed` after safe admission and before a later action from that node; while disconnected, the cleared value appears in the next welcome `input_state`.

**Detail:** Line 260 mutates only the Compose-local `value` state. It never calls `ctx.state(id, "")`, which is the sole path to `DeviceBridge.state` -> `CompanionEngine.publishState` (CompanionEngine.kt:348) -> `SurfaceStore.putDraft` (SurfaceStore.kt:249) and the `state.changed` emission at CompanionEngine.kt:362. Only `onValueChange` (Renderer.kt:273-275) publishes, and clearing does not route through it. Consequently the durable draft in `SurfaceStore.drafts` — which is what `inputState()` (SurfaceStore.kt:236) replays in the welcome — still holds the pre-submit text, while the on-screen field is empty. Both MUSTs in the quoted sentence are unmet: no `state.changed` for the cleared value while READY, and no updated latest input-state value while disconnected.

**Failure scenario:** READY session; `{"t":"text_input","id":"q","clear_on_submit":true,"on_submit":{"action":"note.search"}}`. The user types "orgmode", submits; `event.action` is delivered and the field visibly empties, but no `state.changed {id:"q",value:""}` follows. The transport then drops and reconnects: the welcome `input_state` reports `{"app:main":{"q":"orgmode"}}`. Emacs re-seeds its model with "orgmode" while the Companion shows an empty field — a permanent divergence that the §13.6 reconciliation cannot detect, because the two sides disagree about a draft both consider live.

**Proposed fix:** In `submit()`, after a safe §14.4 admission, call `ctx.state(id, "")` before returning so the clear flows through `publishState` (draft update + ordered `state.changed`) exactly like a user edit, satisfying both the READY and the disconnected branch.

## [P2] [unverified] §17.4 — SpecValidator never checks that an EnumOption `value` is a scalar, so enum_list publishes object/array values in state.changed

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:469  
**SPEC line:** 1952  
**Auditor:** Audit SS17.1 through SS17.3 (the node-type vocabulary preamble, conten

**SPEC quote:**
> An `EnumOption` MUST contain `label` and `value`; `value` MUST be a string, number, or boolean. Option values MUST be distinct under Section 4.3.

**Detail:** The `enum_list` arm (SpecValidator.kt:460-499) validates that each option is an object, that it `has("label")` and `has("value")` (line 469-470), and that option values are distinct under §4.3 (line 471). It never tests the *type* of `opt.get("value")`. §16.1 requires a `1201 content-invalid` rejection for an invalid required field, and §17.4 makes scalar-ness a MUST on the required `value` member. This is W7 audit finding (a) — "accepts an option whose `value` is an object/array (not a scalar)" — which was left unfixed while parts (b) and (c) of the same finding were remediated (the membership and multi-select checks at lines 475-499 are present). `SpecValidatorCompletenessTest.enumListValueMembership` covers membership, multi-select shape and duplicates but has no scalar-type case.

**Failure scenario:** Emacs pushes `{"t":"enum_list","id":"state","on_change":{"action":"s.set"},"options":[{"label":"A","value":{"k":1}},{"label":"B","value":"b"}]}`. Validation accepts it. The user taps chip A: `RenderEnumList.publish()` (InputNodes.kt:272-276) calls `ctx.state("state", <JSONObject{k:1}>)`, which reaches `CompanionEngine.publishState` and emits `state.changed {"id":"state","value":{"k":1}}` and stores the object as the durable draft. Emacs receives a non-scalar enum_list value the SPEC forbids, and the value is replayed in every subsequent welcome `input_state`.

**Proposed fix:** In the `enum_list` arm, after the label/value presence check, add `val ov = opt.get("value"); if (ov !is String && ov !is Number && ov !is Boolean) throw ContentInvalid("$path.options[$i].value", "must be a string, number, or boolean")`, and add the corresponding reject case to SpecValidatorCompletenessTest.

## [P2] [unverified] §17.4 — MenuItem required members (`label`, `on_tap`) are never validated — a menu item with no action is accepted and renders as a dead row

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:407  
**SPEC line:** 1951  
**Auditor:** Audit SS17.1 through SS17.3 (the node-type vocabulary preamble, conten

**SPEC quote:**
> A `MenuItem` MUST contain `label` and `on_tap` and MAY contain `icon` and `enabled`; `enabled` defaults to `true`.

**Detail:** `validateNode`'s `when (t)` (SpecValidator.kt:407-562) has arms for text_input, slider, enum_list, text, rich_text, empty_state, progress, date_stamp, reorderable_list, image, tabs, table, chart, canvas, month_grid and editor — but no arm for `menu`. `NODE_SCHEMA["menu"]` (Vocabulary.kt:53) requires only the key `items`, and the generic loop at lines 404-406 checks presence, not element shape, so `items` is not even required to be an array. The subsequent generic descent (`walkValue`, line 318-338) validates a *present* `on_tap` as an ActionDescriptor but has no way to notice that `on_tap` or `label` is missing. `RenderMenu` (InputNodes.kt:158-174) then builds a `DropdownMenuItem` whose onClick is `item.optJSONObject("on_tap")?.let { onButton(it, ctx) }` — a null-safe no-op. §16.1 requires the whole update to be rejected with `1201` for a missing required member.

**Failure scenario:** Emacs pushes `{"t":"menu","icon":"more","items":[{"label":"Archive","on_tap":{"action":"n.archive"}},{"label":"Delete"}]}`. The surface is accepted. The user opens the overflow menu, taps "Delete", the menu closes, and nothing at all is dispatched — no action, no error, no diagnostic. The SPEC requires the whole `surface.update` to have been rejected with `1201 content-invalid`. The same hole accepts `{"items":"not-an-array"}` (renders an empty menu) and a label-less item that still dispatches an unlabelled action, which also breaches §16.4's "Interactive nodes MUST expose an accessible label".

**Proposed fix:** Add a `"menu" ->` arm to `validateNode`: require `items` to be a JSONArray, and for each element require a JSONObject with a String `label` and an `on_tap` JSONObject (leaving descriptor validation to the existing `walkValue` path), plus a Boolean `enabled` when present.

## [P2] [unverified] §17.4 — enum_list drops an authored off-option selection under allow_add, then silently erases it from the published value

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/InputNodes.kt`:245  
**SPEC line:** 2027  
**Auditor:** Audit SS17.1 through SS17.3 (the node-type vocabulary preamble, conten

**SPEC quote:**
> Unless `allow_add` is true, every selected value MUST appear in `options`. When `allow_add` is true, the Companion MAY accept a new non-empty string value through a local text affordance and MUST publish it like another selection; it does not mutate the authored option list.

**Detail:** `allow_add:true` legalises an authored `value` entry that is not among `options` — SpecValidator honours that (SpecValidator.kt:478-482 skips the membership check when `allowAdd`), and `SurfaceStore.compatible()` honours it too (`|| (node.optBoolean("allow_add") && v is String && v.isNotEmpty())`, SurfaceStore.kt:295). The renderer does not: `seedValues()` (InputNodes.kt:241-246) ends with `return wanted.filter { w -> optionValues.any { jsonValueEquals(w, it) } }`, discarding every authored value that is not an option. The discarded entry does not land in `added`/`selectedAdded` either (those are seeded empty at lines 252-253), so it exists nowhere in the composable's state. `currentValue()` (line 266-270) is built from `selectedValues + selectedAdded`, so the next `publish()` emits a value with the authored entry missing. The `LaunchedEffect(optSig)` prune at lines 259-262 applies the same option-membership filter unconditionally, ignoring `allow_add`.

**Failure scenario:** Emacs pushes `{"t":"enum_list","id":"tags","allow_add":true,"multi_select":true,"on_change":{"action":"tags.set"},"options":[{"label":"Work","value":"work"}],"value":["work","urgent"]}` — legal, and accepted by the validator. The screen shows only the "Work" chip selected; "urgent" is invisible (§16.4: rendering must preserve declared content). The user taps "+ Add" and adds "home": `publish()` emits `state.changed {"id":"tags","value":["work","home"]}` and overwrites the durable draft — the authored "urgent" tag is silently deleted from the note by a user action that meant only to add a tag.

**Proposed fix:** When `allow_add` is true, keep authored values that are not in `options`: seed them into `added` + `selectedAdded` (or keep `selectedValues` unfiltered and render an extra chip for each off-list value), and gate the `LaunchedEffect` prune on `!allowAdd` so a legal locally-added or authored off-list value is not pruned by an options re-push.

## [P2] [unverified] §17.4 — The two clear_on_submit validity rules (`password:true`, builtin `on_submit`) are not enforced by SpecValidator

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:416  
**SPEC line:** 1987  
**Auditor:** Audit SS17.1 through SS17.3 (the node-type vocabulary preamble, conten

**SPEC quote:**
> When `password` is `true`, `value` MUST be absent or the empty string and `on_change` MUST be absent; `clear_on_submit` MUST be absent or `false` because Section 14.6 governs unconditional secret erasure.

**Detail:** The `text_input` arm checks only two of the three password constraints — `if (node.optBoolean("password") && (value is String && value.isNotEmpty() || node.has("on_change")))` (SpecValidator.kt:416-418). `clear_on_submit` is never inspected on a password node. Separately, §17.4 line 2007 states flatly "`clear_on_submit: true` is invalid when `on_submit` is a builtin", and nothing anywhere in the file (or in CompanionEngine/SurfaceStore) tests that pairing; `clear_on_submit` appears in exactly one place in the whole Kotlin tree outside Vocabulary.kt: the renderer at Renderer.kt:260. §16.1 requires a `1201 content-invalid` rejection for a malformed node. `SpecValidatorCompletenessTest` has no case for either rule, and neither does `widgets.golden` (line 43 exercises only the legal remote-on_submit combination).

**Failure scenario:** Emacs pushes a dialog spec containing `{"t":"text_input","id":"name","clear_on_submit":true,"on_submit":{"builtin":"dialog.submit","capture_fields":["name"]}}`. The SPEC declares this invalid and requires `1201`; the Companion accepts it, and on Enter `submit()` fires `dialog.submit` and then blanks the field at Renderer.kt:260 — a clear with no §14.4 admission semantics at all, since a builtin never produces one. The parallel password case `{"t":"text_input","id":"pw","password":true,"clear_on_submit":true,"on_submit":{...}}` is likewise accepted where `1201` is required.

**Proposed fix:** In the `text_input` arm add: `if (node.optBoolean("password") && node.optBoolean("clear_on_submit")) throw ContentInvalid(path, "password nodes must not set clear_on_submit")` and `if (node.optBoolean("clear_on_submit") && node.optJSONObject("on_submit")?.has("builtin") == true) throw ContentInvalid(path, "clear_on_submit is invalid with a builtin on_submit")`. Add both reject cases to SpecValidatorCompletenessTest.

## [P2] [unverified] §17.4 — An app-surface password value is never erased from the composition after the submitted request concludes

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt`:256  
**SPEC line:** 1992  
**Auditor:** Audit SS17.1 through SS17.3 (the node-type vocabulary preamble, conten

**SPEC quote:**
> Password handling MUST obey Section 14.6, and `max_field_bytes` applies while the value is held in volatile memory.

**Detail:** §17.4 delegates password handling to §14.6, whose line 1523-1526 reads: "The Companion MUST hold the value only in volatile memory, place it only in the explicitly submitted action's or dialog result's `fields`, transmit it without durable admission, and erase its local copy as soon as the request concludes or the interaction is cancelled", and line 1537-1541 requires erasure to "remove every locally controlled copy, including the native widget and composition buffer". `RenderTextInput` correctly keeps the secret out of `rememberSaveable` (line 233-234), out of `state.changed` (line 273-278) and out of `args` (line 256 routes it through `actionWithFields`), but the submit path has no erase step: `submit()` (lines 250-261) calls `ctx.actionWithFields(...)` and then, because §17.4 forbids `clear_on_submit` on a password node, falls through line 260 without clearing. `DeviceBridge.actionWithFields` (DeviceBridge.kt:173) is fire-and-forget with an error-only callback, so there is no request-conclusion signal that could drive an erase. The Compose `mutableStateOf` String is precisely the "composition buffer" the SPEC names, and it is trivially controllable.

**Failure scenario:** An `app:*` surface holds `{"t":"text_input","id":"pw","password":true,"on_submit":{"action":"auth.submit","capture_fields":["pw"],"when_offline":"drop"}}` (golden fixture 44). The user types `hunter2` and submits; the `event.action` receives its result and the request concludes. The plaintext remains live in the composable's state for as long as the surface is presented — the masked field still contains it, a second Enter re-submits the same secret without the user re-entering it, and it survives every recomposition. The MUST is to erase it as soon as the request concludes.

**Proposed fix:** Give `DeviceBridge.actionWithFields` a completion callback (the engine's dispatch already has one) and, on conclusion or cancellation, set the password field's state back to "" and drop the `fields` JSONObject reference. Erase on the §14.6 30-second deadline expiry as well, and on the node leaving composition.

## [P2] [unverified] §17.4/§4.5 — No max_field_bytes bound on input values: an oversized draft is published and durably persisted, voiding the §4.5 welcome reservation

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SurfaceStore.kt`:249  
**SPEC line:** 231  
**Auditor:** Audit SS17.1 through SS17.3 (the node-type vocabulary preamble, conten

**SPEC quote:**
> | `max_field_bytes` | REQUIRED, at least `65536` and no greater than `max_frame_bytes - 2048`; maximum encoded bytes per input value, including a volatile password value |

**Detail:** `max_field_bytes` (advertised as 65,536 by DeviceBridge.kt:71) is enforced in exactly two places in the tree — `AppCapabilities.readClipboard` (AppCapabilities.kt:86) and the notification inline reply in `ContextlessEvents.kt:128`. It is never applied to a `text_input`/`editor`/`enum_list` value: `RenderTextInput.onValueChange` (Renderer.kt:266-279) accepts any length, `CompanionEngine.publishState` (CompanionEngine.kt:348-366) has no size test, `SurfaceStore.putDraft` (SurfaceStore.kt:249-257) stores and `persist()`s it durably, and `emit` (CompanionEngine.kt:1676) writes the frame with no cap. `max_input_state_bytes` (262,144) is equally unenforced over the accumulated `drafts` map that `inputState()` (SurfaceStore.kt:236) replays. `checkLimits()` (CompanionEngine.kt:1579-1650) proves `B + max_input_state_bytes - 2 <= max_frame_bytes` at startup, but that proof is only sound if the runtime honours `max_input_state_bytes`, which nothing does.

**Failure scenario:** An `app:*` surface has a multi-line `text_input`. The user pastes a 400 KB text block. The Companion emits `state.changed` with a 400 KB `value` — over six times the `max_field_bytes` it advertised to Emacs in the welcome, so a peer that sized its receive handling to the advertised bound is handed a value it was told could not occur — and writes that value into the durable draft file. On the next reconnect the welcome's `input_state` is ~400 KB, over the advertised `max_input_state_bytes` of 262,144, so the §4.5 reservation the Companion checked at startup no longer holds; with a few such drafts (≈4 MB total) the welcome body exceeds `max_frame_bytes` and, because drafts are durable, the session can never complete a welcome again.

**Proposed fix:** Cap the value at the ingress point: in `publishState`/`putDraft`, reject or truncate a value whose UTF-8 encoding exceeds `limits.max_field_bytes`, and refuse to admit a draft that would push the total `inputState()` encoding past `max_input_state_bytes` (evicting or refusing rather than silently over-running). Mirror the cap in `RenderTextInput.onValueChange` so the user sees the field stop growing rather than losing text at submit.

## [P2] [unverified] §17.5 / §14.3 — `month_grid` local navigation escapes the YYYY-MM domain at the year boundaries, emitting a malformed `on_month_change` value and then crashing the renderer

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/VisualizationNodes.kt`:381  
**SPEC line:** None  
**Auditor:** Audit SS17.4 through SS17.6 (layout nodes, the scaffold and its slots,

**SPEC quote:**
> When an action hook produces a value, the Companion MUST inject it into a copy of `args` under the hook's defined member. … | `on_month_change` | `value` as `YYYY-MM` |

**Detail:** `monthAdd` (VisualizationNodes.kt:381-386) does `total = y*12 + (mo-1) + delta` and formats `"%04d-%02d".format(total/12, total%12 + 1)` with no domain guard. Kotlin Int division truncates toward zero, so a negative total yields a month of 0, and a total ≥ 120000 yields a five-digit year. `changeMonth` (269-275) applies the result whenever the optional `min_month`/`max_month` bounds are absent, and the chevrons are enabled in exactly that case (295, 302). The value is then handed straight to `ctx.action(it, next)` (273) as the §14.3 injected `value`, and the next recomposition parses `shownMonth.substring(0,4).toInt()` / `.substring(5,7).toInt()` (276-277) and indexes `symbols.months[month - 1]` (298). Both authored months pass SpecValidator's `YYYY_MM` regex (SpecValidator.kt:25, 768-771), so this is reachable from an accepted surface.

**Failure scenario:** `{"t":"month_grid","month":"9999-12","on_month_change":{"action":"cal.month"}}` (no `max_month`). The user taps the next-month chevron: `monthAdd` returns `"10000-01"`, an `event.action` is sent with `args.value = "10000-01"` — not a `YYYY-MM` value — and the ensuing recomposition evaluates `"10000-01".substring(5,7)` = `"-0"` → NumberFormatException, crashing the Companion UI. Symmetrically, `month:"0000-01"` + previous-month tap produces `"0000-00"` and `symbols.months[-1]` → ArrayIndexOutOfBoundsException.

**Proposed fix:** Make `monthAdd` total-and-clamped: use `Math.floorDiv(total,12)` / `Math.floorMod(total,12)` and clamp the resulting year to `0..9999`, returning the unchanged month when the step would leave the domain; have `changeMonth` treat an unchanged result as a no-op (no state write, no `on_month_change` dispatch), so navigation can never leave the `YYYY-MM` domain even without authored bounds.

## [P2] [unverified] §17.7 — The at-most-one ${input:} check counts escaped $${input: occurrences, rejecting a SPEC-legal snippet with 1201

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:853  
**SPEC line:** 2152  
**Auditor:** Audit SS17.7 (editor toolbar: snippets, substitution tokens, placement

**SPEC quote:**
> `$${` MUST produce a literal `${` without beginning a placeholder. … A snippet MUST contain at most one `${input:...}` token; a snippet with more than one is an invalid toolbar item.

**Detail:** `INPUT_TOKEN = Regex("""\$\{input:""")` (SpecValidator.kt:31) is matched with `INPUT_TOKEN.findAll(snippet).count() > 1` (line 853). The regex is escape-blind: inside `$${input:x}` the substring starting at index 1 is `${input:` and matches. Per line 2152 that occurrence does not begin a placeholder — the reference substitution engine itself agrees (ToolbarEdits.render checks the `$$ {` escape first, line 45-47, and emits a literal), so the snippet contains exactly ONE `${input:...}` token and is valid. The validator counts two and throws ContentInvalid, which handleSurfaceUpdate converts to `1201 content-invalid` for the entire surface.update (CompanionEngine.kt:604-606).

**Failure scenario:** Emacs pushes a surface whose editor toolbar contains {label:"Template",snippet:"$${input:placeholder} is the literal form; enter yours: ${input:Value}"}. Exactly one live prompt token, one escaped literal — legal under §17.7. SpecValidator counts 2 matches and the WHOLE surface.update is rejected with 1201 content-invalid / path spec…toolbar[0].snippet. The surface never appears; Emacs has no way to express a snippet that inserts the literal text "${input:...}" alongside a real prompt.

**Proposed fix:** Replace the regex count with the same single-pass scanner the runtime uses: walk the string, consume `$${` as a literal (i += 3), and count only `${input:` occurrences reached at a non-escaped `$`. Best done by exporting that scan from ToolbarEdits (e.g. `ToolbarEdits.liveInputTokenCount(snippet)`) so validation and substitution can never disagree; add a test that `"$${input:a} ${input:b}"` is ACCEPTED and `"${input:a} ${input:b}"` is rejected.

## [P2] [unverified] §17.7 — An unadvertised registered toolbar identifier is accepted (no toolbar.<id> features gate), and a test pins the non-conformant behavior

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:809  
**SPEC line:** 2122  
**Auditor:** Audit SS17.7 (editor toolbar: snippets, substitution tokens, placement

**SPEC quote:**
> `editor.toolbar` is either a registered toolbar identifier or an array of ToolbarItem objects. A registered identifier MUST appear as `toolbar.<identifier>` in the applicable profile's `features`; an unknown or unadvertised identifier makes the node invalid.

**Detail:** `validateToolbar` accepts any string matching IDENTIFIER and returns (lines 809-812); its own KDoc defers the check ('profile-features gating happens at the engine's profile check'), but no such check exists — grep for `toolbar` across CompanionEngine.kt, SurfaceStore.kt and Vocabulary.kt finds only the Vocabulary member list, and `Ctx` (line 70-78) carries `advertisedTypes` but no features set. The reference host advertises `APP_FEATURES = IMAGE_FEATURES` only (NodeSupport.kt:65), i.e. zero `toolbar.*` features, so EVERY identifier toolbar is unadvertised and MUST make the node invalid. The renderer then silently drops it: `node.optJSONArray("toolbar")` (Renderer.kt:354) returns null for a String, so no toolbar is drawn. SpecValidatorCompletenessTest.kt:182 asserts `accepts(node("editor","id" to "e","toolbar" to "org-basic"))`, locking in the wrong outcome. (The W7 audit reported the whole toolbar contract as unvalidated; W9 added item validation but not this half.)

**Failure scenario:** Emacs pushes {t:editor,id:body,document:doc:1,toolbar:"org_basic"}. The reference advertises no toolbar.org_basic feature, so §17.7 requires the node to be invalid and the surface rejected with 1201. Instead surface.update returns {status:"applied"} and the editor renders with NO toolbar at all — the exact silent degradation §16.2/§17.7 exist to prevent. Emacs believes its formatting rail is on screen; the user has an editor with no controls and no error anywhere.

**Proposed fix:** Thread the target profile's `features` array into `Ctx` alongside `advertisedTypes` (SurfaceStore.update / handleDialogShow / validateNotificationSpec already pass the profile), and in validateToolbar reject a string identifier when `"toolbar.$toolbar" !in features` with reason 'toolbar-not-advertised'. Flip SpecValidatorCompletenessTest.kt:182 to expect rejection (and add an accepting case with a features set containing toolbar.org-basic). The same threading closes the parallel §17.2 image.https/image.data feature gate.

## [P2] [unverified] §18.1 — dialog.submit reports "" for every captured field the user never touched, instead of the node's current authored value

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt`:537  
**SPEC line:** 2219  
**Auditor:** Audit SS18.1 through SS18.3 (dialogs incl. the dialog.show request and

**SPEC quote:**
> For `dialog.submit`, `fields` MUST be omitted when `capture_fields` is absent or empty and otherwise MUST contain exactly the named current values keyed by node ID.

**Detail:** onButton builds the submit payload as `fields.put(fieldId, dialog.fields[fieldId] ?: "")` (Renderer.kt:533-539). `dialog.fields` is the SnapshotStateMap created empty by RenderDialogRoot (`remember(dialogId) { mutableStateMapOf() }`, Renderer.kt:114) and is written ONLY from RenderCtx.state (Renderer.kt:93-96), which the input renderers call only from their change callbacks — RenderTextInput onValueChange (Renderer.kt:274/277), RenderCheckbox onCheckedChange (InputNodes.kt:192), RenderSwitch (InputNodes.kt:215), enum_list (InputNodes.kt:274), slider (InputNodes.kt:369/386). The authored seed value is read into the local composable state only (Renderer.kt:237 `node.optString("value")`, InputNodes.kt:186/206 `node.optBoolean("checked", false)`) and is never mirrored into dialog.fields. Consequently an untouched captured node resolves through the `?: ""` fallback. This is wrong twice: wrong value (the empty string instead of the node's current value) and wrong JSON type (a string where the stateful node's value schema is boolean/number/array). The engine cannot compensate — completeDialogSubmit (CompanionEngine.kt:1435-1440) copies the supplied `fields` object verbatim. Raised as W7 finding at docs/AUDIT-w7-conformance.md:144 and still unfixed.

**Failure scenario:** Dialog spec {t:"column",children:[{t:"checkbox",id:"agree",label:"I agree",checked:true},{t:"text_input",id:"name",value:"Alice"},{t:"button",label:"OK",on_tap:{builtin:"dialog.submit",capture_fields:["agree","name"]}}]}. The user accepts the pre-filled defaults and taps OK. Emacs receives {"status":"submitted","fields":{"agree":"","name":""}} instead of {"agree":true,"name":"Alice"}. A handler that branches on the boolean sees a string; a rename dialog silently renames to the empty string.

**Proposed fix:** Seed dialog.fields with each stateful node's authored current value at first composition (a LaunchedEffect/SideEffect in each input renderer when ctx.inDialog, or a pre-pass over the dialog spec in RenderDialogRoot that collects {id -> authored value} for every stateful node type), and drop the `?: ""` fallback in onButton so a name that still resolves to nothing is a bug rather than a silent empty string.

## [P2] [unverified] §18.1 — A second outstanding dialog permanently displaces the first, which can then never be completed by the user

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/MainActivity.kt`:55  
**SPEC line:** 2240  
**Auditor:** Audit SS18.1 through SS18.3 (dialogs incl. the dialog.show request and

**SPEC quote:**
> Multiple outstanding dialogs MAY be serialized by the Companion, but request correlation MUST remain intact. A Companion MUST NOT answer one dialog with another dialog's values.

**Detail:** The engine correctly supports several concurrently outstanding dialogs (`dialogs` LinkedHashMap, CompanionEngine.kt:1386) and DeviceBridge advertises `max_dialogs = 4` (DeviceBridge.kt:72), so handleDialogShow accepts up to four before returning 1401 (CompanionEngine.kt:1411-1412). The host presenter, however, is a single slot: `private val currentDialog = MutableStateFlow<Pair<String, JSONObject>?>(null)` (MainActivity.kt:28), and onDialogChanged overwrites it on every show and clears it on every completion (MainActivity.kt:53-57). There is no queue and no re-present step. So when dialog B arrives while A is outstanding, A's modal is destroyed; when B completes, dialogListener(B, null) sets the slot to null and A is never restored. A remains in the engine's `dialogs` map — so it is not answered, and completeDialogSubmit/Dismiss can only be reached from a UI that no longer exists. §18.1 permits serialization (present A, then B), but not dropping A's presentation permanently; the request MUST be kept outstanding *and displayed* until one of the three completion events occurs (line 2211: "The Companion MUST display the node tree modally and keep the request outstanding until one of these occurs"). Not covered by any test: DialogTest.kt exercises the engine's multi-dialog map but never the presenter.

**Failure scenario:** Emacs calls ebp-client-dialog-show twice in quick succession — dialog_id "rename" then dialog_id "confirm-delete" (a realistic pattern when two org commands both prompt). Both are accepted (2 <= max_dialogs 4). Only "confirm-delete" is on screen. The user dismisses it; the screen returns to the app surface with no dialog. "rename" is now unreachable: it is outstanding in the engine but has no UI, so it hangs until ebp.el's `ebp-dialog-timeout` fires 3600 seconds later (ebp.el:50-52, 1261), leaving the Emacs-side callback pending for an hour.

**Proposed fix:** Make the host presenter a FIFO of outstanding dialogs: onDialogChanged(id, spec != null) pushes, onDialogChanged(id, null) removes that id and re-presents the head of the remaining queue. Alternatively, if the host genuinely presents only one, advertise `max_dialogs: 1` so the second show gets the specified 1401 overloaded instead of silently displacing the first.

## [P2] [unverified] §18.1 — dialog.show accepts a remote descriptor with when_offline queue/wake instead of rejecting the dialog 1201

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1414  
**SPEC line:** 2236  
**Auditor:** Audit SS18.1 through SS18.3 (dialogs incl. the dialog.show request and

**SPEC quote:**
> Every such remote ActionDescriptor MUST set or default `when_offline` to `drop`; `queue` and `wake` are invalid because a dialog has no durable instance identity.

**Detail:** handleDialogShow validates the dialog document with `SpecValidator.validateSurfaceSpec(spec, maxCaptureFields=..., maxChartPoints=..., maxCanvasOps=..., advertisedTypes=nodeTypesFromProfiles(config.surfaceProfiles,"dialog"))` (CompanionEngine.kt:1414-1421). There is no dialog flag in that signature (SpecValidator.kt:88-95) and no dialog-aware branch in validateAction; the offline-policy check at SpecValidator.kt:891-897 accepts any of drop/queue/wake so long as ttl_s accompanies the durable ones. So a dialog document authoring `when_offline:"queue", ttl_s:3600` passes and the dialog is displayed. Contrast the pie-menu path, which DOES enforce drop-only (validPieDescriptor, CompanionEngine.kt:792) — the dialog path simply lacks the equivalent. Today the consequence is confined to a wrongly-accepted document because dialog remote actions never dispatch at all (see the dialog_id finding); once that path is added, a naive implementation would durably admit the event, which §18.1 forbids outright because a dialog has no durable identity to replay into. Raised as W7 finding at docs/AUDIT-w7-conformance.md:147 and still unfixed.

**Failure scenario:** Emacs sends dialog.show {dialog_id:"note", spec:{t:"button",label:"Save",on_tap:{action:"note.save",when_offline:"queue",ttl_s:3600,dedupe:"note:1"}}}. §18.1 makes this document invalid, so the Companion must answer 1201 content-invalid. Instead it answers nothing (holds the request) and displays the dialog, so Emacs believes the durable-delivery contract it authored was accepted.

**Proposed fix:** Add an `inDialog: Boolean` (or `allowedOfflinePolicies: Set<String>`) to SpecValidator.Ctx and validateSurfaceSpec, set it from handleDialogShow, and in validateAction's remote branch throw ContentInvalid("$path.when_offline", "a dialog action must be drop") when the effective policy is not drop.

## [P2] [unverified] §18.4 — `ebp-client-theme-set` uses the strict decoder's `:false`/`:null` sentinels, which `json-serialize` rejects on the live jsonrpc.el path — forced-light and mirror-clearing are unreachable; the no-arg call emits `params: null`

**Location:** `emacs/ebp.el`:1160  
**SPEC line:** None  
**Auditor:** Audit emacs/ebp.el as a whole against every SPEC duty assigned to "a c

**SPEC quote:**
> When `dark` is present it forces that polarity; when `dark` is omitted the
Companion follows the device's system light/dark setting. Emacs thus selects
forced-light (`dark: false`), forced-dark (`dark: true`), or follow-system (omit
`dark`).

**Detail:** ebp.el's exported SS6 reference codec configures `:null-object :null :false-object :false` (ebp.el:89-90 parse, 119 serialize), and `ebp-client-theme-set`'s documented API inherits those sentinels: its docstring (ebp.el:1152-1157) says "t forces dark, `:false' forces light" and "the symbol `null' to clear the mirror", and the body emits `:dark :false` / `:colors :null` / `:syntax :null` (ebp.el:1160-1162). But the LIVE path is core jsonrpc.el, which serializes with `:false-object :json-false :null-object nil` (jsonrpc.el:646-648, Emacs 30.1). `:false` and `:null` are therefore unrecognized symbols to `json-serialize`. Verified on the target runtime: `(json-serialize '(:dark :false) :false-object :json-false :null-object nil)` => `(wrong-type-argument json-value-p :false)`; `(json-serialize '(:colors :null) …)` => `(wrong-type-argument json-value-p :null)`. The error is raised inside `jsonrpc-connection-send` before `process-send-string`, so no frame is written and the error propagates back to the application caller. Separately, the all-defaults call produces a nil params plist; `jsonrpc-notify` passes it through and `json-serialize` with `:null-object nil` emits `"params":null` — verified byte-exact as `{"jsonrpc":"2.0","method":"theme.set","params":null}` — violating §7.1 SPEC line 482: "`params` MUST be a JSON object. A method with no parameters MUST send `params: {}`." No ERT test covers `theme.set` (test/ebp-wire-test.el has no theme deftest) and the two smokes only pass `:dark t` (test/smoke-theme.el:32, test/smoke-syntax.el:20), so the broken half of the tri-state is entirely unexercised.

**Failure scenario:** Application selects forced-light: `(ebp-client-theme-set client :dark :false)`. Instead of `{"jsonrpc":"2.0","method":"theme.set","params":{"dark":false}}` on the wire, Emacs signals `(wrong-type-argument json-value-p :false)`, no theme.set frame is ever sent, and the Companion keeps whatever polarity it had. Identically, `(ebp-client-theme-set client :colors 'null)` — the §18.4 way to clear a persisted mirror and select the native scheme — signals `(wrong-type-argument json-value-p :null)`. And `(ebp-client-theme-set client)` (follow-system + native defaults) puts `"params":null` on the wire, which a strict §7.1 receiver must reject.

**Proposed fix:** Translate at the send boundary rather than leaking codec sentinels into the public API: in `ebp-client-theme-set` emit `:json-false` for the false case and `nil` is unusable for JSON null on this path, so pass an explicit `:json-false`/`json-null` marker mapped by a small `ebp--to-wire` normalizer that walks the params plist converting `:false`->`:json-false` and `:null`->a value jsonrpc.el serializes as null (or route theme.set through `ebp--json-serialize` + a raw send). Also replace the empty-params case with `ebp--empty-object` (already defined at ebp.el:121) so `params` is `{}` not `null`, and apply the same normalizer to every other sender so the documented `:false`/`:null` vocabulary is uniform. Add an ERT covering all three `dark` modes and the `colors: null` clear.

## [P2] [unverified] §18.4 — Syntax-role vocabulary never updated for amendment #57: unknown roles `meta`/`paren` are honored (MUST be ignored) while the standard role `tag` is ignored despite having intrinsic per-role styling

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/SyntaxHighlight.kt`:90  
**SPEC line:** 2322  
**Auditor:** Audit SS18.4 (theme.set, color roles, dark tri-state/follow-system fro

**SPEC quote:**
> The standard syntax roles are `comment`, `string`, `keyword`, `function`, `constant`, `variable`, `type`, `number`, `operator`, `preprocessor`, `heading`, `link`, `todo`, `done`, and `tag`; unknown syntax roles MUST be ignored. These are projected into `contract.json` as `syntax_roles`, parallel to `theme_roles`.

**Detail:** Amendment #57 closed the syntax-role vocabulary and projected it into `contract.json` as `syntax_roles` (15 roles). `git log -- render/SyntaxHighlight.kt` shows the file is unchanged since W9-h2 (42aeabe) — it predates #57 and its header comment still asserts the pre-amendment state: "Roles are an open set (the contract fixes no syntax_roles); unknown roles are ignored" (SyntaxHighlight.kt:9-10). The actual consumed set in `emacsSyntaxColors` (SyntaxHighlight.kt:90-107) / `SyntaxColors` (:27-40) is {comment, string, keyword, function, constant, number, link, meta, todo, done, heading, paren}. Two directions of drift: (a) `meta` (:104) and `paren` (:95) are NOT in `syntax_roles`, so they are unknown roles that MUST be ignored, yet a pushed value for either visibly changes rendering; (b) the standard roles `tag`, `variable`, `type`, `operator`, `preprocessor` are never read. `tag` is the sharp case because the highlighter DOES have intrinsic per-role styling for it — `styleOrgLine` paints an org tag run with `SpanStyle(color = c.meta)` at SyntaxHighlight.kt:383 — so §18.4's "PRESENT members override the Companion's own intrinsic per-role styling" is defeated for a role the Companion demonstrably renders. Nothing upstream filters the map: CompanionEngine.handleThemeSet (CompanionEngine.kt:1338-1358) forwards `syntax` verbatim and SpecValidator has no theme code.

**Failure scenario:** Emacs mirrors its theme with `theme.set {"syntax":{"tag":{"fg":"#FF00FF"},"paren":{"fg":"#FF0000"}}}`. Rendering an org document `* TODO ship it :work:` in an `editor` node: the `:work:` tag keeps the Nord fallback `meta` colour (#7B88A1 / #5E6B82) because `tag` is never read, while every rainbow-paren level in an elisp buffer collapses to solid red because the unknown role `paren` (which MUST be ignored) is honored at SyntaxHighlight.kt:95. The author gets the opposite of what was requested in both directions.

**Proposed fix:** Extend `SyntaxColors` with the five missing standard roles (`variable`, `type`, `operator`, `preprocessor`, `tag`) and rename the internal `meta` field to `tag`, wiring SyntaxHighlight.kt:383 (org tags) and :390 (table rows) to it. Drop `paren` and `meta` from the pushed-role lookup in `emacsSyntaxColors` — keep the rainbow-paren list as a purely intrinsic, non-overridable Companion decision (or derive it from the pushed `operator` role, which IS standard). Replace the stale header comment at :9-10 with the closed `syntax_roles` set, and add a pin test asserting `emacsSyntaxColors` reads exactly `contract.json` `syntax_roles` and nothing else.

## [P2] [unverified] §18.5 — Chronometer is handed to the platform unclamped, so an expired or wrong-side `base_ms` renders a negative timer (amendment #60)

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/Notifications.kt`:177  
**SPEC line:** 2345  
**Auditor:** Audit SS18.5 (notification surfaces: meta, priority monotonicity amend

**SPEC quote:**
> `count_down: false` counts elapsed time forward from `base_ms` (which SHOULD be in the past); `count_down: true` counts remaining time down to `base_ms` (which SHOULD be in the future). When `base_ms` is on the wrong side of the current time the Companion presents zero-or-elapsed rather than a negative timer.

**Detail:** Notifications.postSurface lines 177-183 read base_ms and count_down and hand them straight to the platform: `b.setUsesChronometer(true).setShowWhen(true).setWhen(baseMs)` then `b.setChronometerCountDown(chrono.optBoolean("count_down", false))`. There is no comparison against the current time and no clamp anywhere in the file. Android's notification header renders this with android.widget.Chronometer, whose updateText computes `seconds = mCountDown ? mBase - now : now - mBase` and, when that is negative, formats the absolute value through R.string.negative_duration (the "−%1$s" template) — i.e. it displays exactly the negative timer §18.5 forbids. SpecValidator.kt:211-220 validates base_ms only as a non-negative integer and count_down only as a boolean, so nothing upstream rejects or normalizes a wrong-side base either. This is not merely a bad-authoring case: any conformant countdown eventually crosses its own base_ms while still posted.

**Failure scenario:** Emacs posts `notification:pomodoro` with `meta.chronometer = {base_ms: now+300000, count_down: true}` — a well-authored five-minute countdown with base_ms in the future exactly as §18.5 prescribes. The shade counts 5:00 down to 0:00 correctly, then keeps going: at now = base_ms + 72s the header reads "-1:12" and continues decreasing indefinitely, instead of the zero-or-elapsed presentation §18.5 requires. The mirror case (count_down:false with base_ms in the future, e.g. a scheduled task's start time) shows "-4:59" from the moment it is posted.

**Proposed fix:** Clamp before handing the base to the platform: for count_down:true use max(base_ms, now); for count_down:false use min(base_ms, now) (either presents 0:00 rather than a negative). Because a live countdown can cross base_ms while posted, additionally schedule a re-post of that notification at base_ms (an AlarmManager one-shot keyed to the surface) that clears setUsesChronometer or re-clamps the base, so the header freezes at zero instead of going negative.

## [P2] [unverified] §18.6 — The durable reminder store is keyed by `owner` only — not partitioned by pairing identity (amendment #49 unimplemented)

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/ReminderStore.kt`:17  
**SPEC line:** 2408  
**Auditor:** Audit SS18.5 (notification surfaces: meta, priority monotonicity amend

**SPEC quote:**
> A reminder owner set is scoped to the pairing identity: `owner` names an app within one pairing, and one pairing's sets, fired receipts, and platform alarms MUST NOT be visible to or replaceable by another pairing. The durable reminder store MUST be partitioned by pairing identity, so that revocation under Section 9.1 erases exactly that identity's reminders and receipts.

**Detail:** Amendment #49 (2026-07-23) added this MUST; the W8 remediation table records it as a SPEC-only change ("SPEC P2 x5 (#46-#50)") and the impl was never conformed. ReminderStore.kt:17 keys `owners` by owner string alone; the fired-receipt key is `"$owner $id $atMs"` (ReminderStore.kt:31) with no identity component; ReminderState (ReminderBacking.kt:17-20) is Map<owner, List<reminder>>; CompanionStores.kt:88-93 constructs one FileReminderBacking over a single device-wide `ebp-reminders.json`; and Notifications.reminderKey(owner, id) (Notifications.kt:52-57) hashes only (owner, id), so alarm request codes and notification ids are shared across identities. Compare handleTriggersSet (CompanionEngine.kt:1006), which correctly does `val identity = pendingPairingId` and drives TriggerStore.byIdentity — handleRemindersSet (CompanionEngine.kt:869-907) never reads pendingPairingId at all. CompanionConfig.pairings is a Map, i.e. the engine already models multiple pairing identities (DeviceBridge.kt:57-59).

**Failure scenario:** A Companion holds two pairings A and B. A authenticates and calls reminders.set {owner:"org.example.agenda", reminders:[3 entries]}; three alarms are armed. B then authenticates and calls reminders.set {owner:"org.example.agenda", reminders:[]}. handleRemindersSet resolves the same key, ReminderStore.replace() deletes A's three reminders and their receipts, reminderListener -> scheduleReminders cancels A's three platform alarms, and B receives {"count":0} as though it had cleared its own empty set. A's reminders never fire and A is never told. Symmetrically, `max_reminders` (CompanionEngine.kt:891-894) is one global budget across identities so B can starve A, and a §9.1 revocation of B cannot erase B's reminders/receipts without also touching A's.

**Proposed fix:** Key ReminderStore and ReminderState by (pairingId, owner) exactly as TriggerStore.byIdentity does: pass pendingPairingId from handleRemindersSet into reminders.replace/reminder/markFired/isFired, compute totalCount/ownerCount per identity, include the identity in the fired-receipt key and in Notifications.reminderKey's SHA-256 input, and make rearmAllReminders iterate (identity, owner). Add eraseIdentity(pairingId) so §9.1 revocation can drop exactly that partition.

## [P2] [unverified] §19 — A synchronized editor is not read-only when the connection is not READY; offline typing creates an input draft that is silently discarded

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt`:312  
**SPEC line:** 2441  
**Auditor:** Audit SS17.7 (editor toolbar: snippets, substitution tokens, placement

**SPEC quote:**
> A synchronized editor MUST become read-only whenever the connection is not `READY`. It MUST NOT create an offline input draft, delta, save, completion, or editor command.

**Detail:** `readOnly` is derived solely from the node attribute (`node.optBoolean("read_only", false)`, line 312) and the OutlinedTextField is rendered with that flag (line 371); nothing in the render tree observes the session state. MainActivity has no connection-state input at all (its only bridge hook is `onSurfaceChanged`), and DeviceBridge exposes no READY signal to the UI. So while the transport is down the field stays editable and the toolbar stays enabled (line 357 `enabled && !readOnly`): `commit` runs, `value = new` advances the local text (an offline input draft), and `ctx.bridge.editorEdit` posts to the dispatch executor where `localEditorEdit` drops it (`state != SessionState.READY`, CompanionEngine.kt:1138) with no feedback. Snippet/line-op toolbar edits behave identically. (Also raised in docs/AUDIT-w7-conformance.md; the W7 remediation commit f4f65f9 fixed only the `read_only`/`enabled` attributes, not the connection-state rule.)

**Failure scenario:** The user is editing a synchronized note; the phone loses the loopback session (Emacs restarts). Nothing changes visually. The user types two paragraphs. Every keystroke updates the Compose field and is swallowed by localEditorEdit's READY gate. On reconnect the Companion (per §19) must seed the new session from the volatile shadow/cached value — the engine's shadow, which has none of those paragraphs — so edit.open.text disagrees with what is on screen, and the first inbound apply or re-push overwrites the user's work. Nothing ever told the user the editor was disconnected.

**Proposed fix:** Expose the engine's SessionState from DeviceBridge as observable state (e.g. a `ready: StateFlow<Boolean>` set in serve()/close()), thread it into RenderCtx, and compute `val readOnly = node.optBoolean("read_only", false) || (document.isNotEmpty() && !ctx.ready)` so both the field and the toolbar go inert off-READY, with a visible stale/disconnected affordance per §13.5.

## [P2] [unverified] §19.1 — edit.command args carry UTF-16 code-unit offsets where §19.1 requires Unicode-scalar counts

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt`:364  
**SPEC line:** 2485  
**Auditor:** Audit SS17.7 (editor toolbar: snippets, substitution tokens, placement

**SPEC quote:**
> All text positions and lengths are zero-based counts of Unicode scalar values. Ranges are half-open. A Companion whose native editor uses UTF-16 code units or grapheme indices MUST convert before sending and after receiving.

**Detail:** RenderEditor's onCommand closure passes `value.selection.start` / `value.selection.end` straight through: `ctx.editorCommand(document, id, command, value.selection.start, value.selection.start, value.selection.end)`. Compose `TextRange` offsets index the Kotlin String, i.e. UTF-16 code units. DeviceBridge.editorCommand (DeviceBridge.kt:193) and CompanionEngine.editorCommand (CompanionEngine.kt:1185-1186) put those integers verbatim into args `cursor`/`sel_start`/`sel_end`, which §17.7 line 2165 requires and §19.1 defines in scalars. No `codePointCount`/`offsetByCodePoints` conversion happens anywhere on this path. The sibling local-edit path is correct (Renderer.kt:341 uses `EditorSession.diff`, which works on `codePoints()` arrays), which makes this a genuine inconsistency rather than a project-wide convention.

**Failure scenario:** Document text "😀abc" (4 Unicode scalars, 5 UTF-16 units). The caret sits after "😀a": Compose reports selection.start = 3, but the scalar offset is 2. Tapping a toolbar item {icon:"refile",command:"org-refile"} emits event.action edit.command with args {seq:N, cursor:3, sel_start:3, sel_end:3}. Emacs positions the command one character too far right — for an insert/kill command the edit lands after "b" instead of after "a", silently damaging the buffer; the error grows by one per astral character before the caret. Secondarily, a backward selection (Compose TextRange start > end) emits sel_start > sel_end, contradicting §19.3's paired-selection ordering rule.

**Proposed fix:** Convert at the seam in Renderer.kt:363-364: `val t = value.text; fun sc(o:Int) = t.codePointCount(0, o)` and pass `sc(value.selection.end)` as cursor with `sc(value.selection.min)`/`sc(value.selection.max)` as sel_start/sel_end (min/max also fixes the reversed-selection ordering). Same conversion belongs in any future localEditorCaret caller.

## [P2] [unverified] §19.3 — A failed `edit.delta` never marks the session stale and re-requests resynchronization once per subsequent delta instead of exactly once

**Location:** `emacs/ebp.el`:1007  
**SPEC line:** None  
**Auditor:** Audit emacs/ebp.el as a whole against every SPEC duty assigned to "a c

**SPEC quote:**
> It MUST apply a valid splice atomically. On any failure it MUST mark the
session stale and MUST request resynchronization once; it MUST ignore further
deltas until the resynchronization completes.

**Detail:** `ebp-client--handle-edit-delta` (ebp.el:986-1008) has exactly two failure exits — a length-equation mismatch (ebp.el:1007) and a seq/splice-bounds mismatch (ebp.el:1008) — and both call `ebp-client-edit-resync` directly. No stale marker is recorded in the mirror plist (which carries only `:session :seq :text :cursor`, ebp.el:979-982) and the entry guard at ebp.el:994 tests only `ed` and session equality. Consequently every subsequent delta for the still-current session takes the same failure exit and issues another `edit.resync` request. This exact defect was named in the W7 audit summary (docs/AUDIT-w7-conformance.md:433, "the Emacs delta-failure path resyncs repeatedly instead of once") and the current code is unchanged. Compounding it, `ebp-client-edit-resync`'s callback is `(unless error …)` (ebp.el:1078), so the `1201 content-invalid`/`editor-stale` responses the Companion returns for the redundant requests are silently discarded.

**Failure scenario:** Emacs's mirror for `("doc:notes/123" . "body")` is at seq 4. The Companion coalesces edits and sends `edit.delta` seq 5 whose `len` does not satisfy `len = old_length - del + scalar_length(text)` (e.g. a UTF-16-vs-scalar conversion slip). Emacs's length check at ebp.el:1002 fails and it sends `edit.resync` #1. Before that response arrives the Companion, unaware, sends `edit.delta` seq 6 and seq 7 for the same session; each fails `(= seq (1+ 4))` and triggers `edit.resync` #2 and #3. The Companion answers #1 by closing the old session and minting `session: S2` at seq 0, then answers #2 and #3 with `1201 content-invalid`/`data.reason:"editor-stale"` because the tuple they name is now CLOSED (§19.4). Emacs drops both errors unexamined. Required: exactly one `edit.resync`, with deltas 6 and 7 ignored while it is outstanding.

**Proposed fix:** Add a `:stale` member to the mirror plist. On any delta failure, set `:stale t` and call `ebp-client-edit-resync` only when it was previously nil. Extend the `edit.delta` (and `edit.caret`) entry guard to return immediately when `:stale` is non-nil. Clear `:stale` in `ebp-client-edit-resync`'s success branch when the fresh session is installed (ebp.el:1079-1083). Give that callback an error branch as well (see the related SPEC finding) so a refused resync does not leave the mirror wedged.

## [P2] [unverified] §19.3 — Emacs re-requests resynchronization on every failing delta and never marks the mirror stale or ignores deltas

**Location:** `emacs/ebp.el`:1008  
**SPEC line:** 2564  
**Auditor:** Audit SS17.7 (editor toolbar: snippets, substitution tokens, placement

**SPEC quote:**
> It MUST apply a valid splice atomically. On any failure it MUST mark the session stale and MUST request resynchronization once; it MUST ignore further deltas until the resynchronization completes.

**Detail:** `ebp-client--handle-edit-delta` (ebp.el:986-1008) stores no per-session state flag: the mirror plist is only (:session :seq :text :cursor) (set at ebp.el:975-983). On a seq gap or a `len` mismatch it calls `ebp-client-edit-resync` (lines 1007 and 1008) and returns, leaving `:seq` and `:session` untouched. Every subsequent delta for the same still-current session therefore fails the same check and fires ANOTHER edit.resync request. Nothing ignores deltas while a resync is outstanding. Self-healing is accidental: the Companion's handleEditResync mints a new session on the first request, so the 2nd..Nth resyncs come back 1201 editor-stale and the callback's `(unless error ...)` (ebp.el:1077) silently drops them. §19.2's STALE state is never represented on the Emacs side at all.

**Failure scenario:** The Companion coalesces and emits deltas seq 4..12 during fast typing while Emacs is at seq 3 and misses seq 4 (frame dropped on a decode error). Delta 5 fails the seq check -> resync #1. Deltas 6,7,…,12 arrive before the reply and each fails identically -> resync #2..#8, all carrying the now-dead session ID, all answered 1201 editor-stale. That is 8 request round-trips instead of 1 on the exact path §19.3 bounds to one, and every one of those deltas was processed rather than ignored. With a chatty editor the burst is proportional to the in-flight delta count.

**Proposed fix:** Add a `:stale` member to the mirror plist. On the first reconciliation failure set it, send exactly one edit.resync, and have `ebp-client--handle-edit-delta` (and edit.caret) return immediately while `:stale` is non-nil; the resync callback (ebp.el:1078-1083) already replaces the whole entry, so it clears the flag by construction. Add an ERT case in test/ebp-wire-test.el feeding three out-of-order deltas and asserting exactly one edit.resync on the wire.

## [P2] [unverified] §19.4 — Move-only edit.apply ignores the request's seq: a caret move based on a superseded sequence returns 'applied'

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1222  
**SPEC line:** 2645  
**Auditor:** Audit SS17.7 (editor toolbar: snippets, substitution tokens, placement

**SPEC quote:**
> A move-only form omits all of `start`, `del`, `text`, and `len`, retains the current `seq`, and changes only caret/selection. … A move-only form succeeds only at the current sequence.

**Detail:** The move-only branch (`if (!params.has("start"))`, lines 1222-1231) reads only `cursor`, `sel_start`, `sel_end`; `params.opt("seq")` is never consulted — `seq` is parsed 10 lines later, inside the text-changing branch. So a move-only apply carrying ANY seq value, including one the Companion left behind seconds ago, passes straight to `setCaret` and returns `{status:"applied", seq:<current>}`. §19.4 line 2664 is explicit that this form succeeds only at the current sequence, and line 2650-2651 requires a competing operation based on the old sequence to 'receive or cause a stale outcome'. EditorTest.moveOnlyApplyKeepsSeq (EditorTest.kt:162-173) exercises only the matching-seq case, which is why the missing gate survives. (Reported as P3 in docs/AUDIT-w7-conformance.md; still open at HEAD.)

**Failure scenario:** Session at seq 5, shadow "alpha beta gamma". Emacs, still believing seq is 2 (its apply for seq 3 lost a race and the intervening deltas are still in flight), sends a move-only edit.apply {session:S, seq:2, cursor:6, sel_start:6, sel_end:10} to select the word it thinks is at 6..10. The Companion accepts it against the CURRENT text — where 6..10 is a different word — and replies {status:"applied", seq:5}. The user's selection jumps to text Emacs never meant to select, and Emacs receives 'applied', so it never reconciles or resyncs. The correct outcome is {status:"stale", seq:5}.

**Proposed fix:** In the move-only branch, parse `seq` first and return `{status:"stale", seq:s.seq}` when it is present and != s.seq (rejecting a non-numeric seq with -32602), before touching setCaret. Extend EditorTest.moveOnlyApplyKeepsSeq with a stale-seq case asserting status 'stale' and an unchanged cursor.

## [P2] [unverified] §20.3 — clipboard.read bounds raw UTF-8 content bytes, not the §4.5 canonical (JCS) encoded size, so an over-limit `text` is emitted instead of 1003

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/AppCapabilities.kt`:86  
**SPEC line:** None  
**Auditor:** Audit SS20 (device capability module) against CapabilityCatalog.kt, Co

**SPEC quote:**
> For `clipboard.read`, the canonical encoded size of `text` under Section 4.5
MUST NOT exceed `limits.max_field_bytes`. Oversized or non-scalar clipboard
text MUST receive `1003 cap-failed` with
`data.reason: "clipboard-too-large"`; it MUST NOT be truncated.

**Detail:** Call chain: CompanionEngine.handleCapabilityInvoke (CompanionEngine.kt:1091) -> config.capabilityHandler (AppCapabilities.handler, AppCapabilities.kt:51) -> readClipboard (AppCapabilities.kt:79). The gate is `if (text.toByteArray(Charsets.UTF_8).size > maxFieldBytes)` — the raw content byte count. SPEC §20.3 defers to §4.5 for what "canonical encoded size" means, and SPEC.md:215-217 defines it as "the UTF-8 length of the logical value serialized by the JSON Canonicalization Scheme [RFC8785]" — i.e. the quoted, escaped JSON string, not the raw code-unit bytes. The raw count omits the two surrounding quote octets unconditionally and omits all escape expansion (`\"` = 2 bytes per `"`, `\u00XX` = 6 bytes per control character). There is no JCS/canonical-size helper anywhere in the wire library (grep for `jcs|canonical` in companion/wire/src/main returns only TriggerStore.canonicalEquals, a structural comparator). This was reported by the W7 audit (docs/AUDIT-w7-conformance.md:192) and is still unremediated in the current tree. There is also no unit test for AppCapabilities at all (companion/app/src/test contains no capability test); the only exercise is the device smoke test/smoke-capability.el, so the branch is uncovered.

**Failure scenario:** limits.max_field_bytes = 65536 (DeviceBridge.kt:71). The user copies a 60,000-character JSON snippet containing 20,000 `"` characters. readClipboard measures 60,000 raw UTF-8 bytes <= 65,536 and returns Ok({text: ...}). The JCS-encoded value is 2 + 60,000 + 20,000 = 80,002 bytes, over the advertised cap; the Companion emits a `text` field the SPEC says MUST have produced `1003 cap-failed` with `data.reason: "clipboard-too-large"`. With control characters the divergence is up to 6x: 12,000 U+0001 characters measure 12,000 raw bytes but encode to 72,002 JCS bytes.

**Proposed fix:** Measure the JCS serialization of the string value, not the raw content: compute the encoded length as 2 + sum over code points of (escape length), or simply `JSONObject().put("text", text).toString()`-style quoting minus the fixed wrapper, and compare that to maxFieldBytes. Better: hoist a shared `WireLimits.jcsStringBytes(s: String): Int` into companion/wire and use it here and at ContextlessEvents.kt:128 (which has the same raw-byte measurement for the §18.5 inline reply).

## [P2] [unverified] §20.3 — clipboard.read never rejects non-scalar clipboard text; an unpaired surrogate is silently replaced with '?' instead of receiving 1003 cap-failed

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/AppCapabilities.kt`:82  
**SPEC line:** None  
**Auditor:** Audit SS20 (device capability module) against CapabilityCatalog.kt, Co

**SPEC quote:**
> Oversized or non-scalar clipboard
text MUST receive `1003 cap-failed` with
`data.reason: "clipboard-too-large"`; it MUST NOT be truncated.

**Detail:** readClipboard (AppCapabilities.kt:79-89) does exactly two things with the platform value: `clip.getItemAt(0).coerceToText(context).toString()` and a size comparison. There is no scalar-validity check on any path (grep for `surrogate|isWellFormed|codePoint` in companion/app/src/main returns nothing in this file). Unlike every Args string, clipboard text does not arrive through the strict frame decoder — it comes from another application's ClipData, so a Java String holding an unpaired surrogate reaches this function intact. SPEC §4.1 (SPEC.md:120-123) independently requires that "every string and member name MUST be a sequence of Unicode scalar values", and §20.3 names the exact remedy for clipboard text that is not: 1003 with reason clipboard-too-large. Instead the value flows to CompanionOutcome.Ok -> respondResult -> emit -> `JSONObject.toString().toByteArray(Charsets.UTF_8)` (CompanionEngine.kt:1092, emit at the bottom of CompanionEngine.kt), and Kotlin/Java's UTF-8 encoder replaces the malformed surrogate with '?' (0x3F). Reported by the W7 audit (docs/AUDIT-w7-conformance.md:197) and still unremediated.

**Failure scenario:** Another app places a CharSequence containing a lone high surrogate U+D800 on the primary clip (e.g. a text editor that truncated a string mid-astral-pair). Emacs invokes capability.invoke {cap:"clipboard.read"}. Expected per §20.3: error 1003 with data.reason "clipboard-too-large". Actual: a 200-response whose `text` has the surrogate silently rewritten as '?', so Emacs stores corrupted clipboard content with no indication anything was altered — the "MUST NOT be truncated" companion clause is also breached in spirit (the value is mutated, not refused).

**Proposed fix:** Before the size check in readClipboard, scan `text` for unpaired surrogates (iterate chars: a high surrogate must be immediately followed by a low surrogate and vice versa) and return `CapabilityOutcome.Fail(1003, "clipboard-too-large")` when the sequence is not a valid scalar sequence.

## [P2] [unverified] §20.3 — ebp.el's capability client never validates the closed catalog Result, so an invalid Result is delivered to the caller as success

**Location:** `emacs/ebp.el`:1187  
**SPEC line:** None  
**Auditor:** Audit SS20 (device capability module) against CapabilityCatalog.kt, Co

**SPEC quote:**
> Every Args and Result object shown in the catalog is closed. A member suffixed
with `?` is optional; every other shown member is REQUIRED. Invalid Args MUST
receive `-32602` before side effects. Success results MUST NOT add
implementation-private members. An invalid Result is a protocol violation: the
caller MUST fail its local invocation, SHOULD send one safe `log.error`, and
MUST NOT answer the response with another response.

**Detail:** `ebp-client-capability-invoke` (emacs/ebp.el:1187-1199) is the Emacs endpoint's §20 client: it constructs the capability.invoke request and is therefore "the caller" whose local invocation §20.3 obligates. Its success path is `(lambda (result error) (when callback (funcall callback result error)))` — the result plist is handed to the application verbatim with ERROR nil and no shape check against the catalog row: no required-member check, no closed-member check, no per-row type check. There is no result-validation table anywhere in ebp.el (the file's only closed-schema table is `ebp--welcome-required` at line 640, for the welcome). §24.3 makes this binding: "An implementation claiming an optional module MUST implement every REQUIRED method, state transition, type, and failure rule in that module." The `log.error` half of the sentence is W10 and legitimately absent (PLANNED-GAP), but "the caller MUST fail its local invocation" is not W10 work. The docstring at ebp.el:1190-1191 even instructs callers to treat an empty/nil RESULT as success ("exactly one is non-nil except for the {} result ... check ERROR, not RESULT"), which is precisely the reading that makes an invalid Result indistinguishable from a conformant `{}`.

**Failure scenario:** A Companion (buggy, older, or hostile — the local trust boundary in §23.6 is weak) answers `capability.invoke {cap:"clipboard.read"}` with `{"result":{}}` — the REQUIRED `text` member missing. ebp.el invokes CALLBACK with RESULT = nil and ERROR = nil. Following the function's own docstring, the application checks ERROR, sees nil, treats the invocation as successful, and reads `(plist-get result :text)` -> nil, silently proceeding with an empty clipboard. §20.3 requires the caller to fail the local invocation instead. The same hole passes through a Result carrying an implementation-private member (`{"text":"x","debug":"..."}`), which §20.3 explicitly forbids the Companion from sending and which the caller therefore must reject.

**Proposed fix:** Add a per-row Result schema table to the §20 client section of ebp.el (cap -> (required-keys . optional-keys)) mirroring CapabilityCatalog's Args table, and in the success lambda validate that the result plist has exactly the required members, no unknown members, and the row's scalar types. On mismatch call CALLBACK with RESULT nil and a synthetic local error (e.g. `'(:code -32603 :message "invalid capability result")`) rather than reporting success; leave the `log.error` emission for W10.

## [P2] [unverified] §21.1 — `recover()` re-applies a superseded registration's one-shot / throttle / every_s records to a FRESH registration with the same ID

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/TriggerFiringService.kt`:246  
**SPEC line:** 2945  
**Auditor:** Audit SS21 (device trigger module) end to end — SS21.1 trigger.set rep

**SPEC quote:**
> A changed or removed ID MUST
discard every such registration-state record; re-adding it later is a fresh
registration and establishes a new silent baseline, schedule anchor, and boot
generation.

**Detail:** `recover()` walks `queue.firedRecords()` — every record still in `ebp-queue.json`, regardless of when it was admitted (DurableQueue.kt:231-233) — and matches each surviving `trigger.fired` to a live registration by `(trigger_identity, args.id)` ONLY: `val reg = store.registration(identity, id) ?: continue` (line 246). It then unconditionally floors `reg.throttleFloorMs = occurred` (247-249) and, for `time`, sets `reg.oneShotCompleted = true` (252-254) or floors `reg.lastFireFloorMs` (254-257). Nothing distinguishes the registration *generation* that produced the queued record from the current one. `TriggerStore.replace` correctly hands a changed ID a fresh `Registration` with all records cleared (TriggerStore.kt:93-95), and nothing durable records the acceptance epoch (`PersistedRegistration`, TriggerBacking.kt:17-24, has no acceptance timestamp), so recovery silently resurrects exactly the records §21.1 requires be discarded. The existing test `recoverReconstructsOneShotAndEverySMarkers` (FiringServiceTest.kt:204) only covers the unchanged case.

**Failure scenario:** Phone is away from Emacs. `{"id":"standup","type":"time","params":{"at_ms":<Mon 09:00>},"policy":"queue","ttl_s":604800}` fires Monday 09:00 and its `trigger.fired` record sits in `ebp-queue.json` behind a ~200-record offline backlog. Emacs reconnects; the pump drains FIFO one event at a time and, while the backlog is still draining, Emacs pushes an updated set in which `standup` now has `at_ms = <Tue 09:00>` — a CHANGED entry, so `TriggerStore.replace` builds a fresh Registration with `oneShotCompleted=false` (correct, and `at_ms` is future so the §21.5 acceptance check passes). Android then kills the backgrounded process before the backlog finished draining. On the next start `EbpApplication.onCreate -> firing.recover()` finds Monday's still-queued record for id `standup`, sets `oneShotCompleted = true` on the FRESH registration and persists it. `timeSchedule()` now omits `standup`, no alarm is ever armed, and Tuesday's accepted one-shot never fires — permanently, even though `triggers.set` returned `{count:N}` including it. The throttle variant is easier still: a changed `battery.level` trigger with `throttle_s:3600` is re-floored from the old registration's occurrence and suppresses a legitimate crossing for up to an hour.

**Proposed fix:** Stamp each registration with a durable acceptance epoch (a monotonically increasing `generationSeq` or `acceptedAtMs` in `PersistedRegistration`), copy it into the queued record next to `trigger_identity` in `TriggerFiringService.admit` (line 167-168), and in `recover()` skip any record whose stamp does not match the current registration's. Add a FiringServiceTest case: queue a `trigger.fired` for id X, replace X with a changed entry, run `recover()`, assert the fresh registration's `oneShotCompleted`/`throttleFloorMs`/`lastFireFloorMs` are untouched.

## [P2] [unverified] §21.4 — `on_fire` capability `args` are never validated at install time — an unsatisfiable local response is accepted and silently never runs

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/TriggerValidator.kt`:336  
**SPEC line:** 3019  
**Auditor:** Audit SS21 (device trigger module) end to end — SS21.1 trigger.set rep

**SPEC quote:**
> The Companion MUST validate every entry when installing the set.
An unavailable permission MAY leave the trigger registered but unarmed; an
unknown operation MUST reject the entire set.

**Detail:** `TriggerValidator.normOnFire` checks only that `cap` is an identifier, is not in `FORBIDDEN_TRIGGER_CAPS`, is a member of `device.trigger_caps`, and that `args` — if present — is a JSONObject (lines 329-338). It never calls `CapabilityCatalog.validateArgs(cap, args)`, even though that function exists and is the exact §20.3 closed-Args schema. At fire time `TriggerFiringService.executeOnFire` DOES run it (line 209) and swallows a `ContentInvalid` with a bare `return` (210-212), and `TriggerRuntime` wraps every entry in `catch (_: Exception)` (TriggerRuntime.kt:301). Net effect: a structurally impossible local response is accepted with `{count:N}`, reported to Emacs as armed, and can never execute or report anything. The same asymmetry exists for `capability.invoke`, where the identical args ARE validated before acceptance.

**Failure scenario:** `triggers.set` with `{"id":"buzz","type":"boot","policy":"drop","on_fire":[{"cap":"vibrate","args":{"ms":0}}]}` on the reference Android profile (`trigger_caps:["vibrate"]`). §20.3 requires `vibrate.ms` to be an integer 1..60000, so `validateArgs` rejects `ms:0`. The Companion nonetheless replies `{"count":1}` instead of `1101 triggers-rejected`. On the next device boot the trigger is admitted, `executeOnFire` calls `validateArgs`, catches `ContentInvalid`, and returns — the phone never vibrates and nothing is reported. Same for `{"cap":"vibrate","args":{"ms":500,"pattern":[1]}}` (both members) or `{"cap":"vibrate","args":{"nope":1}}`.

**Proposed fix:** In `normOnFire`'s `isCap` branch, after the `trigger_caps` membership check, call `CapabilityCatalog.validateArgs(cap, e.optJSONObject("args") ?: JSONObject())` and let the `ContentInvalid` propagate to the 1101 mapping in `handleTriggersSet`. Because a `${...}` token is always a string (§21.4), either (a) validate with substitution tokens replaced by a schema-satisfying placeholder for the declared type, or (b) resolve the SPEC gap reported separately and validate literally. Add a TriggerTest case asserting 1101 for an out-of-range/unknown-member `on_fire` cap args.

## [P2] [unverified] §21.5 — `recover()` never reconstructs the boot-generation receipt after a torn A/B durable commit

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/TriggerFiringService.kt`:250  
**SPEC line:** 3156  
**Auditor:** Audit SS21 (device trigger module) end to end — SS21.1 trigger.set rep

**SPEC quote:**
> it MUST NOT substitute the
delivery of a single boot signal for a durable generation gate, and the
at-most-once-per-boot guarantee MUST hold even if that boot signal is
redelivered.

**Detail:** The §21.2 step-3 "one transaction" is implemented as two durable writes: A = `queue.admit(...)` into `ebp-queue.json` (TriggerFiringService.kt:165) and B = `store.persistRecords()` into `ebp-triggers.json` (TriggerRuntime.kt:287). A B-throw is compensated by `queue.deleteRecord` (line 177), but a process death between A and B is not. `recover()` exists precisely to close that window and explicitly reconstructs the throttle floor, the one-shot completed marker, and the every_s last-fire floor — but its reconstruction block is gated on `if (reg.entry.getString("type") == "time" && params != null)` (line 251), so the boot-generation receipt is the one exactly-once marker it omits. `reg.bootGeneration` is the sole gate in `tryAdmit` (`if (gen != null && gen == reg.bootGeneration) return`, TriggerRuntime.kt:252-255); after a torn commit it holds the PRE-boot generation on disk, so the gate is open again for the current boot. A boot trigger typically carries no `throttle_s`, so the throttle reconstruction at line 247 provides no cover.

**Failure scenario:** `{"id":"resync","type":"boot","policy":"queue","ttl_s":86400}` is registered during boot generation 6, so `reg.bootGeneration = "6"`. The device reboots (BOOT_COUNT = 7). `BootReceiver` -> `observeExternal("boot", {})` -> `queue.admit` writes the `trigger.fired` record durably (A). The cold-started process is killed by the OS under boot-time memory pressure before `persistRecords()` (B) completes — `goAsync()` gives no protection against a low-memory kill. `ebp-triggers.json` still says `boot_generation:"6"`. On the next process start `recover()` clears pending-local and floors nothing for `resync`. Any redelivery of the boot signal to `observeExternal("boot", …)` in generation 7 now passes the gate (`"7" != "6"`) and admits a SECOND `trigger.fired` for the same device boot, which §21.5 forbids unconditionally, explicitly including the redelivery case.

**Proposed fix:** Extend `recover()`'s reconstruction to boot: for each surviving `trigger.fired` whose registration `type == "boot"`, set `reg.bootGeneration = bootGeneration()` (or carry the generation in the queued event's `args.data`/record so recovery can re-assert the exact generation that produced it) and mark `changed = true`. Cover it with a FiringServiceTest mirroring `recoverReconstructsOneShotAndEverySMarkers`.

## [P2] [unverified] §21.5 — `onExternal` admits every registration of a type without applying that registration's `params` filter

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/TriggerRuntime.kt`:147  
**SPEC line:** 3066  
**Auditor:** Audit SS21 (device trigger module) end to end — SS21.1 trigger.set rep

**SPEC quote:**
> An omitted `params` object means “match every occurrence” where that concept is
defined. Registering a type absent from `device.trigger_types` MUST be rejected.
Every trigger params object and predicate is closed: an unknown member or enum
value MUST reject the complete replace-set rather than broaden a filter.

**Detail:** `TriggerRuntime.onExternal` is `for (reg in store.registrations(identity)) if (reg.entry.getString("type") == type) tryAdmit(reg, data)` — it matches on the trigger TYPE only and never consults `reg.entry.params`. This is the documented route for `package`, `sms.received`, `network`, `calendar.event` and `call.state`-style external occurrences (see the KDoc at TriggerRuntime.kt:142-146 and `TriggerFiringService.observeExternal`, line 87-88). By contrast the level path DOES filter: `onSample` applies `batterySide` / `enumMatch` from `params` (TriggerRuntime.kt:130-136), so the design plainly intends the runtime, not the host source, to own filtering. The validator faithfully normalizes and preserves `params.package`, `params.event`, `params.from`, `params.contains`, `params.calendar`, `params.title_contains`, `params.transport` (TriggerValidator.kt:163-214) — those normalized filters are then never read by any code path. Latent on the shipped Android profile only because `AppCapabilities.TRIGGER_TYPES` advertises just `battery.level/boot/time/timezone.changed` (AppCapabilities.kt:32), all of whose params are `{}`; the wire library is the reference protocol implementation and is host-agnostic.

**Failure scenario:** A host advertises `package` in `device.trigger_types` and feeds `observeExternal("package", {"event":"removed","package":"com.example.other"})`. A registration `{"id":"watch-foo","type":"package","params":{"event":"added","package":"com.example.foo"},"policy":"queue","ttl_s":3600}` is admitted and emits `{"action":"trigger.fired","args":{"id":"watch-foo","type":"package","data":{"event":"removed","package":"com.example.other"}}}` — an occurrence for the wrong package and the wrong event, i.e. the closed filter was broadened to "match every occurrence", which §21.5 forbids. With `sms.received` and `params:{"from":"+15551234"}` the same defect delivers every SMS sender's fire data to Emacs.

**Proposed fix:** Add a `paramsMatch(reg.entry, type, data)` predicate to `TriggerRuntime` mirroring the per-type filter semantics of §21.5 (exact case-sensitive code-point equality for `package`/`calendar`/`from`/`number`; contiguous case-sensitive substring for `contains`/`title_contains`; enum equality for `event`/`state`/`transport`; absent member = no filter) and gate `onExternal`'s `tryAdmit` on it. Add a TriggerRuntimeTest asserting a `package` registration with a `package`+`event` filter is not admitted by a non-matching occurrence.

## [P2] [unverified] §4.1 — capability.invoke coerces an explicit `"args": null` to `{}`, executing a side effect for a request that MUST be -32602

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1072  
**SPEC line:** None  
**Auditor:** Audit SS20 (device capability module) against CapabilityCatalog.kt, Co

**SPEC quote:**
> An absent member and a member whose value is `null` are distinct. A sender MUST
omit an optional member when it has no value unless the member's definition
explicitly permits `null`. A receiver MUST NOT coerce among strings, numbers,
booleans, arrays, objects, and `null`.

**Detail:** handleCapabilityInvoke reads `val args = when (val a = params.opt("args")) { null, JSONObject.NULL -> JSONObject(); is JSONObject -> a; else -> return respondError(id, -32602, ...) }` (CompanionEngine.kt:1071-1075). org.json stores a parsed JSON `null` as the sentinel `JSONObject.NULL`, so the branch deliberately treats a PRESENT member whose value is `null` identically to an ABSENT member. §20.2 (SPEC.md:2749-2750) defines the default only for absence — "`args` defaults to `{}`" — and the §20.3 Args object for every row is closed, so `null` is not a permitted value for `args`. The Companion is the strict-receiver side under §6.2/amendment #34, and the rest of the library gets this right: TriggerValidator.normTrigger (TriggerValidator.kt:75-79) routes `JSONObject.NULL` into its `else ->` throw branch, rejecting `params: null`. capability.invoke is the outlier. Reported by the W7 audit (docs/AUDIT-w7-conformance.md:394) and unremediated. Note this is not merely cosmetic for zero-arg rows: those are exactly the rows where the coerced `{}` passes validation.

**Failure scenario:** Emacs (or any local process that completed the handshake) sends `{"jsonrpc":"2.0","id":"1","method":"capability.invoke","params":{"cap":"clipboard.read","args":null}}`. Expected: `-32602 invalid-params` with no side effect. Actual: `args` becomes `{}`, CapabilityCatalog.validateArgs("clipboard.read", {}) passes (CapabilityCatalog.kt:81), the handler runs, the device clipboard is read, and the clipboard contents are returned in the result — a side effect performed for a message the receiver was required to reject.

**Proposed fix:** Split the branch so only true absence defaults: `val args = when (val a = params.opt("args")) { null -> JSONObject(); is JSONObject -> a; else -> return respondError(id, -32602, "Invalid params", "invalid-params") }` (JSONObject.NULL is not a JSONObject, so it falls into `else`, matching TriggerValidator's shape).

## [P2] [unverified] §4.1 / §6.2 — Companion accepts non-RFC8259 bodies: NaN/Infinity, unquoted and single-quoted keys, trailing commas — silently coerced to strings

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/FrameCodec.kt`:138  
**SPEC line:** 118  
**Auditor:** Audit SS4.1 through SS4.4 (JSON data model: value types, object/duplic

**SPEC quote:**
> JSON bodies MUST conform to [RFC8259] and MUST be encoded as UTF-8 without a byte-order mark.

**Detail:** `parseBody` decodes with `JSONTokener.nextValue()` (FrameCodec.kt:138-148), which is deliberately lenient. Verified by running the pinned org.json 20240303 jar: `{"a":NaN}` -> JSONObject with the STRING "NaN"; `{"a":Infinity}` and `{"a":-Infinity}` -> strings; `{a:1}` (unquoted key) -> accepted; `{'a':1}` (single quotes) -> accepted; `{"a":1,}` (trailing comma) -> accepted; `{"a":0x10}` and `{"a":01}` -> strings "0x10"/"01". None of these is RFC 8259 JSON, and §6.2 requires "invalid UTF-8 or invalid JSON MUST produce a JSON-RPC Parse Error with `id: null`" — an obligation §6.2 marks REQUIRED for the Companion. Worse than mere tolerance, the tokener performs exactly the conversion §4.1 forbids ("A receiver MUST NOT coerce among strings, numbers, booleans, arrays, objects, and `null`"): a bare non-JSON literal becomes a JSON string, so a receiver-side type test that should fail closed instead succeeds. The Emacs twin rejects all of these (verified: `{"a":NaN}` -> json-parse-error), so a body one endpoint calls a Parse Error the other renders.

**Failure scenario:** A frame carries `surface.update` with spec `{"t":"text","text":NaN}`. The Companion MUST answer -32700 Parse Error. Instead JSONTokener yields `text` = the string "NaN", SpecValidator's `text` node passes (nothing type-checks `text` beyond the schema's required-member presence), and the surface renders the literal word "NaN". Same vector with `enum_list` options: `{"label":"A","value":NaN}` becomes the string "NaN", is accepted as a distinct option value under §4.3, and is published verbatim in `state.changed` — Emacs receives a string where it authored (invalid) numeric syntax.

**Proposed fix:** Do not let JSONTokener define the accepted grammar. Either (a) gate `parseBody` with a strict RFC 8259 pre-scanner (the depth scan at FrameCodec.kt:162 is already a linear pass over the same text — extend it into a validating tokenizer that rejects unquoted literals other than true/false/null, single quotes, trailing commas, leading zeroes, hex, and the NaN/Infinity words), or (b) replace org.json at the ingress boundary with a strict parser and convert to JSONObject afterwards. Option (a) keeps the zero-dependency and Android-parity property the file documents.

## [P2] [unverified] §4.2 — Non-finite numbers accepted where §4.2 requires a finite binary64; infinite slider bounds crash state publication

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:447  
**SPEC line:** 145  
**Auditor:** Audit SS4.1 through SS4.4 (JSON data model: value types, object/duplic

**SPEC quote:**
> A JSON number used where this document says `number` MUST convert under round-to-nearest, ties-to-even to a finite IEEE-754 binary64 value.

**Detail:** org.json parses `1e999` into a BigDecimal whose `toDouble()` is Infinity (verified by execution with the pinned jar). SpecValidator's numeric guards are inconsistent about that: the slider continuous branch (SpecValidator.kt:447-457) reads `min`/`max` with `(node.opt(...) as? Number)?.toDouble()` and only tests `min >= max` and `v.isNaN()` — never `isInfinite()`; `validatePositiveInt` (589-594) tests `n != Math.floor(n) || n < 1`, and Math.floor(Infinity) == Infinity so Infinity passes as a "positive integer"; `date_stamp.year` (518-522) and `validateCanvas`'s width/height (709-714) have the same hole. Other sites in the very same file DO check (`ttl_s` at 904 tests `d.isInfinite()`, chart points at 687, canvas op coordinates at 731), and CompanionEngine's `surfaceRevision` (CompanionEngine.kt:553-559) range-checks against 9007199254740991 — so the codebase already knows the rule and applies it unevenly. §17.4 independently states "Slider `value`, `min`, and `max` are finite numbers".

**Failure scenario:** Emacs pushes `{"t":"slider","id":"s","max":1e999}`. SpecValidator accepts (0.0 >= Infinity is false). RenderSlider reads `node.optDouble("max",1.0).toFloat()` = Float.POSITIVE_INFINITY (InputNodes.kt:378) and builds `valueRange = 0f..Infinity` (line 389). Compose's fraction math `(pos-min)/(max-min)` yields NaN/Infinity (verified: fraction = NaN for an infinite range), so on gesture commit `ctx.state(id, pos.toDouble())` (line 386) reaches `CompanionEngine.publishState`, which does `.put("value", value)` (CompanionEngine.kt:365). org.json's testValidity throws `JSONException: JSON does not allow non-finite numbers` (verified by execution) — the state.changed emission throws inside the dispatch path instead of the surface having been rejected with 1201 at push time. Same class, no crash: `{"t":"text","text":"hi","max_lines":1e999}` passes validatePositiveInt and then `optInt` returns 0 (verified), silently discarding the constraint.

**Proposed fix:** Add one shared helper (e.g. `private fun finiteNumber(v: Any?): Double?` returning null unless `v is Number && v.toDouble().isFinite()`, plus `ebpInteger(v)` additionally requiring integrality and |v| <= 9007199254740991) and route every numeric read in SpecValidator through it: slider min/max/value/values, validatePositiveInt, validateIntRange, date_stamp.year, canvas width/height, chart height. Reject with ContentInvalid, matching the existing ttl_s treatment.

## [P2] [unverified] §4.4 / §4.5 (with §14.1) — Action names get no §4.4 identifier grammar and no 128-octet cap at any site (nor does `dedupe`)

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:887  
**SPEC line:** 170  
**Auditor:** Audit SS4.1 through SS4.4 (JSON data model: value types, object/duplic

**SPEC quote:**
> Unless a narrower grammar is stated, an EBP identifier MUST: - contain 1 through 128 ASCII characters; - begin with an ASCII letter or digit; and - contain only ASCII letters, digits, `.`, `_`, `-`, `:`, and `/`.

**Detail:** §14.1's ActionDescriptor table types `action` as a "namespaced identifier" (SPEC.md:1223) and `dedupe` as an "identifier" (SPEC.md:1226); §14.1's prose narrows only the dot rule ("An action name MUST contain at least one dot", SPEC.md:1231), so the §4.4 grammar and §4.5's "Identifier | 128 UTF-8 octets and the ASCII grammar above" still govern. `SpecValidator.validateAction` (SpecValidator.kt:887-890) checks only `obj.opt("action") as? String` and `'.' !in name` — no character class, no length. `dedupe` is never validated at all in the surface path (Vocabulary.kt:69 lists it as merely optional; ContextlessEvents.kt:66 reads it with `optString`). The same omission repeats in `validateNotificationAction` (SpecValidator.kt:277-280), and two further sites drop even the dot rule: `validateReminder`'s on_tap (CompanionEngine.kt:930-931, `onTap.opt("action") !is String` only) and `validPieDescriptor` (CompanionEngine.kt:791, same). Contrast CompanionEngine.kt:866, which does define a capped `Regex("[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}")` for reminder owner/id, cap names, and menu_id — the cap is simply never applied to the most security-relevant identifier the protocol carries (§3 item 5: "A transmitted operation name ... MUST be treated as untrusted data and MUST be validated").

**Failure scenario:** Emacs pushes a surface containing `{"t":"button","label":"Go","on_tap":{"action":"note." + 300 arbitrary chars including U+000A and spaces}}`. §4.5 requires the receiver to reject the identifier; SpecValidator accepts the whole document. The user taps, the Companion mints `event.action` with that `action` value and durably admits it to the queue, and delivers it to Emacs. A conformant Emacs endpoint that enforces §4.4 on the incoming `action` answers -32602, so under §15.3 the event is dropped — the tap is lost permanently, whereas the SPEC's §13.2 whole-document validation was supposed to have refused the surface at push time.

**Proposed fix:** Introduce a single `fun isIdentifier(s: String) = IDENT_128.matches(s) && s.toByteArray(Charsets.UTF_8).size <= 128` in the wire package (the node-id site at SpecValidator.kt:393-395 already does exactly this) and apply it to `action` (after the dot check) and `dedupe` in `validateAction` and `validateNotificationAction`, and to the `action` member in `validateReminder` and `validPieDescriptor` (which also need the missing dot check).

## [P2] [unverified] §4.5 — checkLimits never requires `max_device_report_bytes`, so a Companion granting `capabilities`/`triggers` can emit an unbounded, unreserved device report

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1641  
**SPEC line:** None  
**Auditor:** Audit SS20 (device capability module) against CapabilityCatalog.kt, Co

**SPEC quote:**
> | `max_device_report_bytes` | REQUIRED when `capabilities` or `triggers` is granted; maximum canonical bytes of the complete device report |

**Detail:** checkLimits (CompanionEngine.kt:1583, called from init at line 85) enforces hard floors for the core limits via floor() (lines 1594-1598) but treats every conditional limit as optional. For the device report it computes `val deviceBudget = if (emitsReport) l.optLong("max_device_report_bytes", 0) else 0` (line 1641), then guards the size check with `if (deviceBudget > 0)` (line 1642) and adds `deviceBudget` into the §4.5 reservation inequality at line 1647. When the host omits the member, deviceBudget is 0: the `require(config.deviceReport... <= deviceBudget)` bound is skipped entirely AND the reservation is computed as if no device member were emitted — even though buildWelcome (CompanionEngine.kt:1560-1574) unconditionally adds `device` to the welcome whenever `capabilities` or `triggers` is granted. The W7 remediation (commit 2df38ba) added the budget term but conditioned it on the limit's presence rather than requiring it, so the reservation soundness hole reopens for any host that forgets the member. The member is also absent from the welcome `limits` in that case, so Emacs cannot size anything either. DeviceBridge.kt:75 does set it to 8192, so the shipping app is conformant; the reference library is not.

**Failure scenario:** A host builds CompanionConfig with supportedCapabilities containing "capabilities", a limits object matching DeviceBridge's minus `max_device_report_bytes`, and a device report that lists `app.launch` with a `launchable_packages` array of 3,000 package names (~120 KB). checkLimits passes: the report is never bounded and deviceBudget is 0, so the reservation `B + 0 + max_input_state_bytes - 2 <= max_frame_bytes` succeeds. At handshake, buildWelcome emits the 120 KB device member on top of a near-worst-case `surfaces`/`input_state` welcome; the body exceeds max_frame_bytes and encodeFrame (FrameCodec.kt) throws FrameClose, killing the connection at the exact moment the §4.5 reservation exists to make impossible.

**Proposed fix:** In checkLimits, when `emitsReport` is true, require the member's presence and positivity before using it: `require(l.optLong("max_device_report_bytes", -1) > 0) { "limits.max_device_report_bytes is REQUIRED when capabilities or triggers is supported" }`, and drop the `if (deviceBudget > 0)` guard so the report-size require always runs. Apply the same conditional-presence discipline to max_dialogs / max_pie_menus / max_reminders / max_triggers / max_trigger_responses / max_editor_sessions, which are equally unchecked.

## [P2] [unverified] §4.5 — max_chart_points and max_canvas_ops are enforced per node instead of aggregated across the SurfaceSpec, so a document can carry many multiples of the advertised cap

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:672  
**SPEC line:** None  
**Auditor:** Audit SS4.5 (limits and bounds) exhaustively. Enumerate EVERY limit na

**SPEC quote:**
> Unless a row states otherwise, `max_canvas_ops`, `max_chart_points`, `max_rich_spans`, and `max_table_cells` are aggregate counts across one SurfaceSpec or dialog document.

**Detail:** validateChart declares `var totalPoints = 0L` as a local at SpecValidator.kt:672 and checks it at line 680 — the accumulator resets for every `chart` node, so the limit is per-node, not per-document. validateCanvas checks `ops.length().toLong() > ctx.maxCanvasOps` at SpecValidator.kt:718, likewise per-node. The traversal context SpecValidator.Ctx (lines 70-83) holds maxChartPoints/maxCanvasOps but no running totals — only `var nodeCount` is document-scoped, proving the aggregate pattern was available and not used. §17.5 (SPEC.md:2047-2100) states nothing that would override §4.5's default aggregate rule for either limit, so the aggregate reading governs. The engine passes the real advertised values (CompanionEngine.kt:43-44 for surfaces, 1416-1417 for dialogs), so this is not a test-only default. No test in companion/wire/src/test or companion/app/src/test references max_chart_points or max_canvas_ops at all, which is why the divergence ships green.

**Failure scenario:** Shipped config advertises max_chart_points=4096 and max_canvas_ops=4096 (DeviceBridge.kt:85). A surface.update whose spec is a column of 70 `chart` nodes, each with one series of 4096 points ({"x":0,"y":0} = 13 bytes, ~3.9 MB total, within max_frame_bytes and only 71 nodes so the 10,000-node limit is untouched), is accepted: each node's local totalPoints reaches exactly 4096 and passes. The document holds 286,720 chart points — 70x the advertised aggregate — and is persisted and handed to VisualizationNodes to draw. The minimal violation needs only two chart nodes of 4096 points each (8192 > 4096). Identically, 70 `canvas` nodes of 4096 ops each yield 286,720 ops against a 4096 cap.

**Proposed fix:** Move the accumulators into Ctx: add `var chartPoints = 0L` and `var canvasOps = 0L` alongside `nodeCount`, have validateChart do `ctx.chartPoints += points.length()` and test `ctx.chartPoints > ctx.maxChartPoints`, and have validateCanvas do `ctx.canvasOps += ops.length()` and test `ctx.canvasOps > ctx.maxCanvasOps`. Add tests that two charts/canvases whose combined counts exceed the limit are rejected while a single at-limit node is accepted.

## [P2] [unverified] §4.5 (with §4.4) — SpecValidator's IDENTIFIER regex omits the 128-octet cap at six identifier sites

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:21  
**SPEC line:** 186  
**Auditor:** Audit SS4.1 through SS4.4 (JSON data model: value types, object/duplic

**SPEC quote:**
> A receiver MUST enforce all of the following limits: ... | Identifier | 128 UTF-8 octets and the ASCII grammar above |

**Detail:** `private val IDENTIFIER = Regex("[A-Za-z0-9][A-Za-z0-9._:/-]*")` (SpecValidator.kt:21) has an unbounded `*` quantifier. It is used for notification `meta.channel` (line 200), `meta.category` (204), notification action `icon` (245), inline-reply `input.key` (259), the `editor.toolbar` registered-toolbar identifier (810), and toolbar `command` (843) — none of which pairs it with a length test. Only the node-`id` site (393-395) adds `id.toByteArray(Charsets.UTF_8).size > WireLimits.MAX_IDENTIFIER_OCTETS`; TriggerValidator.kt:29 and CompanionEngine.kt:866 both bake the bound into the regex as `{0,127}`. So the constant `WireLimits.MAX_IDENTIFIER_OCTETS` exists and is applied at some sites and not others, which is precisely the enforcement gap §4.5 forbids ('A receiver MUST enforce all of the following limits').

**Failure scenario:** Emacs pushes a notification surface whose action carries `input: {"key": "<70,000 ASCII letters>"}`. SpecValidator accepts it (grammar matches, no length test). §18.5 then requires the Companion to "place the submitted text in the resulting `event.action.fields` under that key" — so a user's inline reply produces an event whose `params.fields` member name alone is 70 KB. That event is measured against `max_event_bytes` at admission and, for a reply of any size near the field cap, exceeds it and is refused, so the user's typed reply is silently discarded, where the SPEC required a 1201 content-invalid rejection of the surface push instead.

**Proposed fix:** Change the shared regex to `Regex("[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}")` (matching TriggerValidator.kt:29 and CompanionEngine.kt:866), or better, replace all seven call sites with the single `isIdentifier()` helper proposed for the action-name finding so grammar and octet cap can never drift apart again.

## [P2] [unverified] §4.5 / §4.4 / §14.1 — ActionDescriptor `action` and `dedupe` bypass the §4.5 identifier bound entirely — no grammar check and no 128-octet cap

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:889  
**SPEC line:** None  
**Auditor:** Audit SS4.5 (limits and bounds) exhaustively. Enumerate EVERY limit na

**SPEC quote:**
> A receiver MUST enforce all of the following limits:  …  | Identifier | 128 UTF-8 octets and the ASCII grammar above |  …  (§4.4) Unless a narrower grammar is stated, an EBP identifier MUST: contain 1 through 128 ASCII characters; begin with an ASCII letter or digit; and contain only ASCII letters, digits, `.`, `_`, `-`, `:`, and `/`.

**Detail:** §14.1's descriptor table types `action` as a "namespaced identifier" and `dedupe` as an "identifier" (SPEC.md:1226,1230), so both fall under §4.5's identifier row. SpecValidator.validateAction applies neither rule: the only `action` check is `if ('.' !in name) throw` (SpecValidator.kt:889-890) — no grammar match, no length bound — and `dedupe` is merely listed in ACTION_SCHEMA["remote"].optional (Vocabulary.kt:69) with no validation of any kind (not even its JSON type; dispatchAction later reads it with descriptor.optString("dedupe") at CompanionEngine.kt:307, which coerces a JSON number to a string, contrary to §4.1). The file's own IDENTIFIER regex (SpecValidator.kt:21) is unanchored in length and is applied only to node ids (with a separate explicit 128-octet byte check at line 393-394), notification channel/category/icon/input.key, and toolbar identifier/command. This is a distinct hole from the W7 identifier findings, which were remediated for TriggerValidator (IDENT now `[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}`, TriggerValidator.kt:29) and for the engine's reminder owner/id, cap names, and pie menu_id (CompanionEngine.kt:866) — the ActionDescriptor path was not covered.

**Failure scenario:** Emacs sends surface.update for app:main with {t:"button", label:"x", on_tap:{action:"org todo.set é", when_offline:"queue", ttl_s:3600, dedupe:"k".repeat(50000), args:{}}}. Both the space and the non-ASCII character violate §4.4's grammar and the dedupe key is 50,000 octets, yet validateAction accepts the descriptor and the surface is applied and persisted. On tap, dispatchAction builds params whose UTF-8 size stays under max_event_bytes=262144, so DurableQueue.admit persists a record whose dedupe index key is 50 KB and delivers an event.action whose `action` member is a non-conforming identifier. Substituting action:"a." + "x".repeat(200000) yields a 200,002-octet 'identifier' on the wire, 1,562x the §4.5 bound.

**Proposed fix:** In SpecValidator.validateAction, after the dot check, require the action name to match a length-bounded identifier regex (`[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}` plus a UTF-8 byte check, matching the node-id treatment at SpecValidator.kt:393-394) and reject otherwise with ContentInvalid. Add the same check for `dedupe`, and require it to be a JSON string first so the optString coercion at CompanionEngine.kt:307 can never see a number. Apply the identical checks in validateNotificationAction (SpecValidator.kt:276-294), which duplicates the descriptor rules.

## [P2] [unverified] §6.2 — ebp.el reference decoder accepts a Content-Length value containing a bare LF: `^`/`$` are line anchors in Emacs regexps

**Location:** `emacs/ebp.el`:188  
**SPEC line:** 398  
**Auditor:** Audit SS5 (transport profiles) and SS6 (Content-Length framing) agains

**SPEC quote:**
> A receiver MUST parse header field names case-insensitively. It MAY accept optional horizontal whitespace around a header value. It MUST reject a signed, fractional, empty, non-decimal, or overflowing `Content-Length` value.

**Detail:** `ebp--content-length-re` is "^\\(?:0\\|[1-9][0-9]*\\)$" (ebp.el:188-190) and is applied with `string-match-p` at ebp.el:206. In Emacs regexp syntax `^` matches at the beginning of the string *or after a newline* and `$` matches at the end *or before a newline* — they are line anchors, not string anchors (`\\`` / `\\'` are the string anchors). `ebp--parse-header` splits the header section on "\r\n" only (ebp.el:196), so a header line may legitimately contain a bare LF, and that LF lands inside `value`. The Kotlin twin uses `Regex("0|[1-9][0-9]*").matches(value)` (FrameCodec.kt:94,110), which is a whole-input match and rejects; validate.py uses `re.fullmatch` and rejects. Only the elisp reference decoder accepts. Verified empirically on Emacs 30.1 against this checkout: feeding "Content-Length: 2\nContent-Length: 99\r\n\r\n{}" returns the decoded message with zero pending octets (accepted), and feeding "Content-Length: abc\n5\r\n\r\n{}" signals only `ebp-parse-error` on an empty body — i.e. `string-to-number` yielded 0, a zero-octet body was consumed, and the real body "{}" is left to be misread as the next header section. §6.2 scopes receiver strictness as RECOMMENDED for Emacs only where it "MAY delegate framing and message decoding to a host-platform JSON-RPC library"; this decoder is not a delegation but the exported reference §6 receiver (ebp.el:485-488) that §24.5 conformance suites are driven by, and FrameCodec.kt:3 asserts it is byte-for-byte twinned with the Kotlin one.

**Failure scenario:** Header section `Content-Length: abc\n5\r\n\r\n{"jsonrpc":"2.0",...}`: §6.2 requires the receiver to reject the non-decimal value and close. `ebp-decoder-feed` instead accepts length 0, signals `ebp-parse-error` on the empty body (a recoverable error, not a close), and leaves the real JSON body in the buffer to be parsed as a fresh header section — a desynchronized stream where the SPEC mandates closure. A conformance suite built on this exported decoder would certify the behavior as correct.

**Proposed fix:** Change `ebp--content-length-re` to string anchors: "\\`\\(?:0\\|[1-9][0-9]*\\)\\'". While there, reject any bare CR or LF in `line` inside `ebp--parse-header` as a malformed header line, so the field-name/value grammar cannot straddle an embedded newline. Add a wire golden (bare-LF-bearing Content-Length, `expect_error: close`) so both twins and validate.py pin the behavior.

## [P2] [unverified] §7.1 / §6.2 — Companion strands pipelined frames after a recoverable framing error: a valid request behind a bad frame in the same read is never answered

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:109  
**SPEC line:** 474  
**Auditor:** Audit SS5 (transport profiles) and SS6 (Content-Length framing) agains

**SPEC quote:**
> Every EBP request MUST receive exactly one response unless the connection dies first.

**Detail:** `FrameDecoder.feed` (FrameCodec.kt:55-75) advances `buffer` past a frame *before* parsing its body (`buffer = buffer.copyOfRange(bodyEnd, buffer.size); consumer(parseBody(body))`), so a `WireParseError`/`InvalidRequest` thrown by `parseBody` propagates out of the `while (true)` loop with the stream still synchronized and any *following* complete frames still sitting in `buffer`. `CompanionEngine.feed` catches those two at CompanionEngine.kt:109-118, emits one `-32700`/`-32600` via `emitFramingError`, and returns — it never re-enters the decoder to drain what is left. `DeviceBridge.serve`'s reader (DeviceBridge.kt:313-318) only calls `engine.feed` when `input.read()` returns new bytes, and then blocks in `read()`. So a fully received frame behind the bad one is parsed neither now nor ever, unless unrelated future traffic happens to arrive. The decoder's own KDoc (FrameCodec.kt:48-54) shows the authors thought about the mirror case — "a well-formed frame pipelined *ahead* of a bad one in the same read is not lost" — and handled it with the consumer callback, but the *behind* case is unhandled. §6.2's "the receiver MAY continue the connection after either error" is elected here (state stays open), so §7.1's response obligation still binds. §24.6 items 2 and 3 make exactly this combination ("two frames with no delimiter between the first body and next header" plus "invalid JSON"/"over-deep JSON nesting") a REQUIRED adversarial vector.

**Failure scenario:** Emacs writes a `surface.update` request whose document nests past the 64-container depth limit, immediately followed by a normal `surface.update` request id `s2`; the kernel coalesces both into one loopback `read()`. FrameDecoder throws `WireParseError("nesting depth exceeds 64")` on the first frame; CompanionEngine emits `{id:null, error:{code:-32700}}` and returns. Frame `s2` is complete in `decoder.buffer` but is never dispatched and never answered, while the connection stays open. Emacs's `s2` request hangs until its client-side timeout and the surface is never applied.

**Proposed fix:** Make `CompanionEngine.feed` drain to exhaustion: wrap the decoder call in a loop that, after emitting the `-32700`/`-32600` diagnostic, re-invokes `decoder.feed(ByteArray(0)) { ... }` and repeats until a call completes without throwing a recoverable error (breaking out immediately on `FrameClose`/`FrameIncomplete`, which close). `FrameDecoder.feed` already tolerates an empty `bytes` argument, so no decoder change is required.

## [P2] [unverified] §7.1 / §7.4 (with §6.2) — A decode-level frame error aborts the decoder loop, stalling every frame already pipelined behind it in the same transport read

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:107  
**SPEC line:** 519  
**Auditor:** Audit SS7 (JSON-RPC 2.0 conventions) and SS8 (error model) in both twi

**SPEC quote:**
> Each endpoint MUST parse frames in wire order.

**Detail:** `FrameDecoder.feed` (FrameCodec.kt:55-75) advances `buffer` past a frame's body BEFORE calling `consumer(parseBody(body))`, so a `WireParseError`/`InvalidRequest` thrown from `parseBody` propagates out of the `while (true)` loop with the bad frame already consumed but every SUBSEQUENT complete frame still sitting in `buffer`. `CompanionEngine.feed` (CompanionEngine.kt:95-118) catches those two exceptions, calls `emitFramingError(-32700 | -32600, ..., id:null)`, and returns — it never re-drives the decoder. Because §6.2 permits continuing after either error and the engine does continue, the trailing frames are not discarded; they are simply never handed to `dispatch` until the peer happens to write more bytes. If the peer is blocked awaiting the response to the pipelined request, that never happens and the frame is stranded for the life of the connection, so its request receives no response (§7.1:474). The decoder's own KDoc (FrameCodec.kt:48-54) reasons only about the opposite order ("a well-formed frame pipelined ahead of a bad one in the same read is not lost"), and the suite tests only that direction: CompanionEngineTest.kt:429-444 `aGoodFramePipelinedBeforeABadOneIsNotLost` feeds good-then-bad; nothing feeds bad-then-good. §24.6 item 2 requires the pipelined-frames vector. The exported elisp reference decoder has the identical structure (`ebp-decoder-feed`, ebp.el:241-269, signals out of its `while` with the buffer already advanced).

**Failure scenario:** In one transport read the peer writes `encodeFrame("[1]")` (a prohibited top-level array) immediately followed by `encodeFrame(request("q1","queue.replay",{}))`, then blocks awaiting the `queue.replay` result. `decoder.feed` throws `InvalidRequest` on the first body; `CompanionEngine.feed` emits `{"id":null,"error":{"code":-32600,...}}` and returns. The `queue.replay` frame stays in `decoder.buffer`, is never dispatched and never answered — during §10.3's barrier this hangs synchronization until the request timeout and the durable backlog is never drained.

**Proposed fix:** Re-drive the decoder after emitting a framing error: wrap the body of `CompanionEngine.feed` in a loop that calls `decoder.feed(ByteArray(0)) { ... }` again after the `WireParseError`/`InvalidRequest` catches until a call completes without throwing (bounding iterations; `FrameClose`/`FrameIncomplete` stay terminal). Alternatively have `FrameDecoder.feed` deliver per-frame taxonomy errors to the consumer in wire order instead of throwing out of the loop. Add `aGoodFramePipelinedAfterABadOneIsStillDispatched` to CompanionEngineTest.kt and the mirror ERT case for `ebp-decoder-feed`.

## [P2] [unverified] §7.2 — `ebp-valid-request-id-p` rejects integer request IDs, contradicting §7.2 / amendment #34, and an ERT test pins the wrong behavior

**Location:** `emacs/ebp.el`:289  
**SPEC line:** 487  
**Auditor:** Audit SS7 (JSON-RPC 2.0 conventions) and SS8 (error model) in both twi

**SPEC quote:**
> A request ID MUST be either a JSON string or a JSON integer. A string ID MUST
be an identifier under Section 4.4 of at most 64 ASCII octets and MUST NOT be
empty. An integer ID MUST be a safe integer under Section 4.2. `null` and
fractional numbers MUST NOT be used.

**Detail:** `ebp-valid-request-id-p` (ebp.el:289-293) is `(and (stringp id) (<= 1 (length id) 64) (string-match-p "..." id))` — it implements only the first of §7.2's two legal id forms, and its docstring still reads "SPEC 7.2: a string identifier of at most 64 ASCII octets, never empty", i.e. the pre-amendment-#34 rule. `ebp-request` (ebp.el:295-298) gates on it, so the exported SPEC 7 reference builder cannot construct a conformant integer-id request at all. The Kotlin twin is correct and explicitly annotated: Envelope.kt:14-20 accepts `is Int -> true` and `is Long -> id in -MAX_SAFE..MAX_SAFE`, and WireConformanceTest.kt:149-151 asserts `isValidRequestId(7)` with the comment "amendment #34: jsonrpc.el ids". The elisp ERT suite asserts the opposite: test/ebp-wire-test.el:199 `(should-not (ebp-valid-request-id-p 7))` under the docstring "SPEC 7.2: string identifiers, 1..64 octets." So the two reference twins disagree about the validity of the very id form amendment #34 was written to bless, and the elisp test locks the non-conformant answer in. This matters because ebp.el's decoder/envelope layer is the exported §6/§7 reference for conformance suites: a suite validating a received request id — or an Emacs-originated jsonrpc.el id, which is always an integer — with this predicate judges every legal integer id invalid.

**Failure scenario:** A conformance harness calls `(ebp-valid-request-id-p 7)` on the id of the integer-id frame that amendment #34 appended to `ebp/goldens/frames.golden` specifically to pin this case; the predicate returns nil and the harness reports a conformant golden frame as an id-grammar violation. Equally, `(ebp-request 7 "session.ready" params)` signals "Invalid request id: 7" for an id §7.2 declares legal.

**Proposed fix:** Widen the predicate to §7.2's full grammar: `(or (and (integerp id) (<= -9007199254740991 id 9007199254740991)) (and (stringp id) (<= 1 (length id) ebp-max-request-id-octets) (string-match-p "\\`[A-Za-z0-9][A-Za-z0-9._:/-]*\\'" id)))`, mirroring Envelope.kt:14-20, and update the docstring to cite both forms. Flip test/ebp-wire-test.el:199 to `(should (ebp-valid-request-id-p 7))` and add the safe-integer boundary and fractional cases so it matches WireConformanceTest.kt:149-153.

## [P2] [unverified] §7.3 — A structurally invalid `edit.complete` (missing/non-numeric `seq`) raises a raw Lisp error, producing `-32603 Internal error` with no `error.data` at all

**Location:** `emacs/ebp.el`:1036  
**SPEC line:** None  
**Auditor:** Audit emacs/ebp.el as a whole against every SPEC duty assigned to "a c

**SPEC quote:**
> - Structurally invalid request parameters MUST receive `-32602 invalid-params`.

**Detail:** `ebp-client--handle-edit-complete`'s session/seq guard is `(unless (and ed (equal (plist-get ed :session) (plist-get params :session)) (= (plist-get ed :seq) (plist-get params :seq))) …)` (ebp.el:1035-1038). §19.3 makes `seq` REQUIRED on `edit.complete`. When the peer omits it (or sends it as a string), `(plist-get params :seq)` is nil / a string and the `=` signals `wrong-type-argument` — but only AFTER the `session` `equal` has already passed, so the short-circuit does not save it. jsonrpc.el catches any non-`jsonrpc-error` condition with `(error '(:error (:code -32603 :message "Internal error")))` (jsonrpc.el:314-315), which never populates `:data`. Because `ebp-client--error` was never reached, `ebp--connection-error-data` is nil and the `jsonrpc-convert-to-endpoint` override (ebp.el:460-468) attaches nothing. The reply therefore violates two MUSTs at once: the wrong code (-32603 instead of -32602) and the missing `data.kind` required by §8 SPEC line 545-547 ("An EBP-defined error MUST use a numeric JSON-RPC `error.code`, a concise human-readable `error.message`, and an `error.data` object containing the stable string member `kind`"). The same data-less -32603 is produced for any Lisp error raised inside a registered `event.action` handler, which §15.3 then degrades to `blocked_by: "json-rpc-error"`. A secondary hazard: because `ebp-client--error` is also reachable from the notification dispatcher (see the class-gate finding), a stash left by an unreplied notification-path error can be attached to a LATER unrelated -32603 reply by the override at ebp.el:463-467, mislabelling it with a foreign `kind`.

**Failure scenario:** An editor session for `("doc:notes/123" . "body")` is open at seq 4. The Companion sends `{"jsonrpc":"2.0","id":31,"method":"edit.complete","params":{"document":"doc:notes/123","editor_id":"body","session":"00112233445566778899aabbccddeeff","cursor":7}}` — `seq` omitted. `(= 4 nil)` signals `wrong-type-argument`; Emacs replies `{"jsonrpc":"2.0","id":31,"error":{"code":-32603,"message":"Internal error"}}` with no `data` member. Required: `-32602` with `data.kind:"invalid-params"`. The Companion, which per §19.3 SHOULD trigger a resync on a typed stale and otherwise treats an unknown error as a protocol fault, receives an untyped internal error it cannot classify.

**Proposed fix:** Validate the `edit.complete` envelope before the session/seq comparison: require `document`, `editor_id`, `session` to be strings and `seq`, `cursor` to be non-negative integers, signalling `ebp-client--error client -32602 "Invalid params" "invalid-params"` otherwise; only then compare against the mirror and signal 1201/editor-stale. Apply the same envelope precheck to `edit.open`/`edit.delta`/`edit.caret`/`edit.close` (which currently `=`/`1+` on possibly-nil `seq` too). Additionally, wrap handler invocation so any escaping non-`jsonrpc-error` condition is converted to `-32603` WITH `data.kind:"internal-error"`, and clear `ebp--connection-error-data` on entry to every dispatch rather than opportunistically inside `jsonrpc-convert-to-endpoint`.

## [P2] [unverified] §9.1 — No rate limiting of failed proofs anywhere: unlimited reconnect-and-retry against the pairing token

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1519  
**SPEC line:** 620  
**Auditor:** Audit SS9 (pairing and mutual authentication) against companion/wire/A

**SPEC quote:**
> The Companion MUST rate-limit failed proofs per pairing ID and source process or connection. It MUST NOT reveal whether an unknown pairing ID or an incorrect proof caused authentication failure.

**Detail:** `handleAuth` verifies the proof and, on failure, emits 1203 and closes (lines 1519-1528). There is no counter, backoff, lockout, or delay of any kind — grep for `throttle|rateLimit|failedProof` across companion/ returns only trigger-throttle code (TriggerRuntime/TriggerStore), nothing in Auth.kt, CompanionEngine.kt, or DeviceBridge.kt. Because the engine is constructed fresh per socket (DeviceBridge.kt:237) and `CompanionConfig` holds no cross-connection failure state, every reconnect resets whatever per-connection state exists. The accept loop (DeviceBridge.kt:127-131) has no connection-rate cap either. The failure is therefore keyed to nothing that survives the close the SPEC itself mandates.

**Failure scenario:** A local process loops: connect to 127.0.0.1:8765, send a valid `session.hello` for the known (non-secret) pairing ID, send `auth.response` with a guessed 64-hex `client_proof`, receive 1203, socket closes, repeat. The Companion imposes no delay and never fences the pairing ID, so attempts run at loopback speed indefinitely. Each iteration also triggers the §5.2 finding above, so the same loop is simultaneously a permanent denial of the paired Emacs session.

**Proposed fix:** Add a process-wide (not per-engine) failure ledger in the app host, keyed by pairing ID, persisted across process restarts: on each 1203, increment and apply exponential backoff (e.g. refuse `auth.response` with 1203 without computing the HMAC once N failures occurred inside a window, and reject new connections for that pairing ID for the backoff period). Inject it into `CompanionConfig` so the wire engine consults it in `handleAuth` before the `verifyClientProof` call at CompanionEngine.kt:1522, and clear it on a successful authentication.

## [P2] [unverified] §9.1 — §9.1 pairing lifecycle is entirely unimplemented: no CSPRNG generation, no revocation, and no per-store erase for queue/drafts/surfaces/tombstones/theme/reminders/triggers

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/DeviceBridge.kt`:57  
**SPEC line:** 607  
**Auditor:** Audit SS9 (pairing and mutual authentication) against companion/wire/A

**SPEC quote:**
> The Companion MUST provide explicit pairing revocation. Revocation MUST atomically fence the identity from new authentication, close its active sessions, erase its token, queued payloads, input drafts, cached surfaces, tombstones, themes, reminders, triggers, and identity-scoped shortcuts, and withdraw identity-scoped visible artifacts where the platform permits.

**Detail:** Two halves are both absent. (a) Generation: `CompanionConfig.pairings` is a hard-coded literal — `mapOf("101112131415161718191a1b1c1d1e1f" to EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw"))` (DeviceBridge.kt:57-59). That is the SPEC's own published §9.3 known-answer token (SPEC.md:681) and pairing ID, so the shipped app's HMAC key is public; nothing calls a CSPRNG to satisfy "The Companion MUST generate two independent values with a cryptographically secure random number generator" (SPEC.md:590). The code comment marks it "W4 SMOKE SCOPE … before the pairing UI exists", but there is no build-variant gate and no rung in docs/REWRITE-PLAN.md that fixes it (W10 is §22 overload only). (b) Revocation: no revoke/unpair entry point exists anywhere (`grep -ri 'revoke|unpair|forget|purge'` over companion/ hits only comments). More fundamentally there is no API to erase with: `DurableQueue` (admit/sweepExpired/deleteRecord/clearInFlight), `SurfaceStore` (update/remove/putDraft/snapshot), `ReminderStore` (replace/markFired), and `TriggerStore` (replace/persistRecords) expose no identity-scoped or wholesale erase, and `CompanionStores` (the sole constructor of all four file backings, plus `ebp-theme.json` written by DeviceBridge.kt:100-105) exposes no teardown. `ReminderStore` and `SurfaceStore`/`DurableQueue` are not even keyed by pairing ID, so a per-identity erase is not expressible against the current durable formats.

**Failure scenario:** A user pairs, uses the device (queued offline events with captured `fields`, retained input drafts including a partially typed note, cached `app:*` surfaces and tombstones, a mirrored theme, 20 reminders, 12 triggers), then decides to unpair. There is no way to do it: no UI, no method, no store call. All of that data stays in `filesDir/ebp-queue.json`, `ebp-surfaces.json`, `ebp-reminders.json`, `ebp-triggers.json`, `ebp-theme.json` indefinitely, and — because the token is the published KAT — any local process can still authenticate and read it back via the welcome snapshot and `queue.replay`. §23.3's "Durable event payloads and captured input snapshots MUST be deleted after … pairing revocation" is unreachable for the same reason.

**Proposed fix:** Add `fun eraseIdentity(pairingId: String)` to each of DurableQueue, SurfaceStore, ReminderStore, TriggerStore (deleting the backing file content, not just the in-memory map), plus theme-file deletion, and a `CompanionStores.revoke(ctx, pairingId)` that (1) fences the id out of `CompanionConfig.pairings` first, (2) closes the live session, (3) calls each store's erase, (4) cancels platform artifacts via Notifications/TriggerAlarms. Separately, replace the hard-coded KAT `pairings` map with a persisted, CSPRNG-generated 16-octet token + 16-octet pairing ID (display as 22-char base64url / 32 lowercase hex per §9.1), and until the pairing UI lands gate the KAT credential behind a debug build variant so a release build cannot ship a public HMAC key.

## [P3] [unverified] SS14.4 — ebp.el returns `accepted` with no durable receipt when SQLite is unavailable and :receipt-file is nil

**Location:** `emacs/ebp.el`:861  
**SPEC line:** 1426  
**Auditor:** Audit SS14.4 through SS14.6 (the event.action request protocol, EventI

**SPEC quote:**
> Before returning `accepted`, Emacs MUST durably commit the EventId together with either the completed application effect or a durable work item that owns that effect. If it cannot make that commitment, it MUST return `1500 event-retry`. Returning `accepted` merely because a volatile callback was scheduled is not conforming.

**Detail:** ebp-client--receipt-commit (ebp.el:847-871) has three branches. With an open SQLite handle it INSERTs; with SQLite available but no handle it deliberately signals so the caller answers 1500 (ebp.el:858-860); the fallback branch (ebp.el:861-868) wraps the write in `when-let*` on :receipt-file. When that plist member is present and nil — ebp-connect only defaults it via `(unless (plist-member config :receipt-file) ...)` (ebp.el:532-534), so an explicit nil is preserved — the when-let* body is skipped, no bytes are written, and control still falls through to `(puthash event-id now ...)` and `t` (ebp.el:869-870). The handler therefore replies {:status "accepted"} (ebp.el:907-909) on the strength of an in-memory hash table alone, which is exactly the volatile commitment the SPEC names as non-conforming. The SQLite-present branch masks this on a typical Emacs 30.1 build, so the defect is confined to an Emacs built without --with-sqlite3.

**Failure scenario:** An Emacs built without SQLite support (the plan's own note flags this as VERIFY on the on-device Android Emacs) connects with (ebp-connect ... :receipt-file nil). A queued event.action arrives, the handler returns 'accepted, ebp-client--receipt-commit writes nothing and returns t, and the Companion deletes the durable record. Emacs then restarts; the receipts hash is empty and the same logical occurrence, if redelivered by any other route, is executed a second time instead of answering `duplicate` — and, worse, the deletion was authorized by a commitment that never existed.

**Proposed fix:** Make the fallback branch total: `(t (let ((file (plist-get (ebp-client-config client) :receipt-file))) (unless file (error "no durable receipt store")) (let ((write-region-inhibit-fsync nil)) (write-region ...))))`. Equivalently, reject a nil :receipt-file at ebp-connect time, or document it as a conformance-off test mode and have the event.action handler answer 1500 while it is in force.

## [P3] [unverified] §13.1 (§24.2) — ebp.el keeps per-surface revisions only in memory — the endpoint's "MUST persist its next revision" is unimplemented

**Location:** `emacs/ebp.el`:503  
**SPEC line:** 1009  
**Auditor:** Audit SS13.1 through SS13.4 (surface namespaces, surface.update / surf

**SPEC quote:**
> One surface is owned by the pairing identity and has one ordered history of snapshots and tombstones. Emacs MUST assign revisions monotonically per surface and MUST persist its next revision. Gaps are allowed. Revisions MUST NOT wrap. (SPEC.md:1008-1011)

**Detail:** The revision map is a bare struct slot, `(revisions (make-hash-table :test #'equal))` (ebp.el:503), with no durable backing — contrast the EventId receipts on the very next lines, which do have `:receipt-file` / `ebp-client--receipts-load` (ebp.el:506-507, 558). `ebp-client--surface-floor` defaults a missing entry to -1 (ebp.el:1088-1089) and `ebp-client--surface-request` claims `(1+ floor)` at send time (ebp.el:1101-1103). `ebp-connect` builds a FRESH client per connection (ebp.el:1271) and a closed client is terminal (ebp.el:568-579), so after any reconnect or Emacs restart the map starts empty and the entire revision history is re-derived from the welcome's `surfaces` floors (ebp.el:670-673). §24.2 lists "persistent monotonic per-surface revisions and absorption of Companion revision/tombstone floors" (SPEC.md:3446) as an endpoint MUST — the second half is implemented, the first is not, so the redundancy the SPEC deliberately requires on both sides is absent and the Companion's report is the only authority.

**Failure scenario:** Emacs writes surface.update {surface:"app:main", revision:42, spec:A} and the socket dies before the Companion reads the frame; the Companion's floor stays 41. Emacs reconnects (fresh client, empty revision map), absorbs floor 41 from the welcome, and its next push for app:main is again revision 42, now carrying spec B. Two different snapshots have been assigned the same revision for one surface, which §13.1's monotonic rule exists to prevent. It becomes observable through DeviceBridge's SPEC 5.2 newest-wins handover (DeviceBridge.kt:128-131): the superseded connection's engine shares the same SurfaceStore, so a frame already buffered by the old reader — the original revision-42/spec-A update — can be applied after the new session's revision-42/spec-B update, leaving the device showing A with a floor of 42 and no way for either side to detect the regression.

**Proposed fix:** Persist the revision map beside the receipts: write `(surface . next-revision)` to a small file under `user-emacs-directory` (or into the existing receipt sqlite db) on every claim in `ebp-client--surface-request`, load it in `ebp-client-create`, and make welcome absorption at ebp.el:670-673 use `max` of the reported floor and the persisted value (`ebp-client--absorb-floor` already does exactly that) instead of an unconditional `puthash`.

## [P3] [unverified] §13.2 (§23.5) — stale_spec is validated without the advertised max_chart_points / max_canvas_ops (residual of the remediated W9-I15)

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SurfaceStore.kt`:156  
**SPEC line:** 1045  
**Auditor:** Audit SS13.1 through SS13.4 (surface namespaces, surface.update / surf

**SPEC quote:**
> The Companion MUST validate the entire request before changing persistent or visible state. (SPEC.md:1045)  ...  They MUST bound decoded images, base64 payloads, canvas operations, rich-text spans, table cells, chart points, trigger registrations, reminders, editor sessions, and outstanding dialogs. They MUST reject excessive content atomically and MUST NOT partially execute a rejected object. (SPEC.md:3396-3399)

**Detail:** The app branch calls `staleSpec?.let { SpecValidator.validateStaleSpec(it, spec.has("views")) }` (SurfaceStore.kt:156), and validateStaleSpec forwards to `validateSurfaceSpec(staleSpec, "stale_spec")` with every limit defaulted (SpecValidator.kt:152-153) — i.e. maxChartPoints = maxCanvasOps = Long.MAX_VALUE (SpecValidator.kt:92-93) — while the primary `spec` two lines earlier is validated with the store's real values (SurfaceStore.kt:150-153; 4096/4096 from CompanionStores.kt:77). The W9 audit's I15 named both the notification-body call and this stale_spec call; the RB-7 remediation threaded the limits into validateNotificationSpec (SurfaceStore.kt:142-144 now passes them) but left validateStaleSpec's defaults untouched, so the asymmetry survives on the core app path.

**Failure scenario:** surface.update {surface:"app:main", revision:2, spec:{t:"text",text:"hi"}, stale_spec:{t:"canvas", width:100, height:100, ops:[ ... 1,000,000 line ops ... ]}} is answered {status:"applied"} even though the advertised max_canvas_ops is 4096 and the identical node inside `spec` is correctly rejected with 1201. The oversized document is fully parsed and structurally validated (validateCanvas runs over every op) before being discarded, so a nonconforming sender gets unbounded validation work per request that the advertised limit is supposed to cap.

**Proposed fix:** Give validateStaleSpec maxCaptureFields/maxChartPoints/maxCanvasOps parameters (and, for symmetry with the primary spec, advertisedTypes) and pass the store's fields from SurfaceStore.kt:156, exactly as lines 150-153 and 142-144 already do.

## [P3] [CONFIRMED] §14.1 — An action name is checked only for a dot, not against the §4.4 identifier grammar; `dedupe` is not validated at all

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:889  
**SPEC line:** 1234  
**Auditor:** Audit SS14.1 through SS14.3 (ActionDescriptor shape, the dotted action

**SPEC quote:**
> An action name MUST contain at least one dot and MUST be registered in an
explicit Emacs-side allowlist.

**Detail:** The §14.1 member table (SPEC.md:1223) types `action` as a "namespaced identifier" and `dedupe` as an "identifier", so §4.4 applies: 1-128 ASCII characters, beginning with a letter or digit, containing only letters, digits, `.`, `_`, `-`, `:`, `/`. SpecValidator.validateAction enforces only `if ('.' !in name)` (SpecValidator.kt:889-890) and never touches `dedupe` — the private `IDENTIFIER` regex and `WireLimits.MAX_IDENTIFIER_OCTETS` at SpecValidator.kt:21/394 are applied to node ids, icons, toolbar commands, notification channel/category/input.key, but not to either descriptor member. The notification-action copy of the same logic has the same gap (SpecValidator.kt:279-280). §16.1 (SPEC.md:1682) makes an "invalid action descriptor" a whole-update 1201.

**Failure scenario:** `{t:"button", label:"x", on_tap:{action:".", when_offline:"queue", ttl_s:60, dedupe:"<8 KiB of arbitrary UTF-8 including spaces and control characters>"}}` is accepted at surface.update. On tap, dispatchAction emits `event.action` with `action:"."` — not a namespaced identifier — and DurableQueue.admit stores the 8 KiB dedupe key in the queue record (DurableQueue.kt:118, used as the compaction key at 129-133), where it counts against max_queued_bytes and is compared on every later admission. Both members were required to be 1-128 ASCII identifier characters.

**Proposed fix:** In SpecValidator.validateAction, after the dot check, also require `IDENTIFIER.matches(name)` and `name.toByteArray(Charsets.UTF_8).size <= WireLimits.MAX_IDENTIFIER_OCTETS`; add the same pair of checks for `dedupe` when present. Apply the identical two lines in validateNotificationAction (SpecValidator.kt:276-294) so the notification path does not drift. Tests: action `"."`, action `"a b.c"`, a 129-character action, and a non-identifier/over-long `dedupe` each produce 1201.

**Verdicts:**
- `SPEC TEXT` refuted=False (high): SPEC.md:1223/1226 types `action` as "namespaced identifier" and `dedupe` as "identifier" in §14.1's normative member table; §4.4 (SPEC.md:170-175) binds that term unconditionally — "Unless a narrower grammar is stated, an EBP identifier MUST: contain 1 through 128 ASCII characters; begin with an ASCII letter or digit; and contain only ASCII letters, digits, `.`, `_`, `-`, `:`, and `/`" — and the §
- `CODE TRUTH` refuted=False (high): Code reproduces the claim exactly. SpecValidator.kt:889-890 is the whole action-name check (`if ('.' !in name) throw ContentInvalid("$path.action", "action names contain a dot")`) — the file's `IDENTIFIER = Regex("[A-Za-z0-9][A-Za-z0-9._:/-]*")` (line 21) and `WireLimits.MAX_IDENTIFIER_OCTETS` (used at 393-394 for node ids) are never applied to it, and the notification copy at 279-280 is identical
- `MATERIALITY` refuted=False (high): The gap is real, live, in scope, and untested. SPEC.md:168-175 (§4.4) applies "unless a narrower grammar is stated"; §14.1's table (SPEC.md:1223/1226) states no narrower grammar for `action` or `dedupe`; SPEC.md:1682 (§16.1) makes an "invalid action descriptor" a whole-update 1201. SpecValidator.kt:889-890 enforces only `if ('.' !in name)`, so `action: "."` — which violates §4.4's "begin with an A

## [P3] [unverified] §15.2 — The expiry count for the "next replay summary" is process-local, so expiry deletions performed by the auto-delivery pump are lost across a restart

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/DurableQueue.kt`:51  
**SPEC line:** 1576  
**Auditor:** Audit SS15 (durable queue and replay) against DurableQueue.kt, QueueSt

**SPEC quote:**
> It MUST delete expired records before delivery
and MUST count them in the next replay summary.

**Detail:** `pendingExpired` (DurableQueue.kt:49-52) is a plain in-memory `Int`, explicitly documented as "In-memory: informational count". It is incremented in `sweepExpired` (DurableQueue.kt:176) and drained only by `takeExpiredCount()` (DurableQueue.kt:182) from `concludeReplay` (CompanionEngine.kt:548). Neither `QueueSnapshot` (QueueStore.kt:15-19) nor the persisted JSON (`records`/`next_seq`/`clock_high_water`, QueueStore.kt:53-56) carries it, and `DurableQueue.init` (DurableQueue.kt:54-59) starts it at 0.

The record deletions themselves ARE durable — `sweepExpired` replaces `records` and calls `persist()` at DurableQueue.kt:168-171 — so after a restart the events are gone but the obligation to report them in the next replay summary cannot be met. The welcome-time sweep (`CompanionEngine.kt:1550`) happens in the same process as the first replay, so the common reconnect path is fine; the loss window is a sweep performed by the auto-delivery pump (`beginDelivery` → `sweepExpired`, DurableQueue.kt:83) whose count is never consumed because no `queue.replay` is active, followed by process death.

**Failure scenario:** READY session; three `ttl_s: 60` records have aged out. A new durable admission calls `pumpAdvance` → `beginDelivery(null)` → `sweepExpired()` deletes the three, persists the shortened `ebp-queue.json`, and sets `pendingExpired = 3`. The head delivers, is `accepted`, and `pumpAdvance` reaches `Delivery.Empty` → `concludeReplay`, which returns at CompanionEngine.kt:543 because `replayId` is null, so the 3 is never drained. Android then kills the process for memory. On restart and reconnect, Emacs's §10.3 `queue.replay` returns `{"delivered":0,"rejected":0,"expired":0,"remaining":0,"blocked_by":null}` — three events were deleted by expiry and reported as zero, so Emacs cannot distinguish "nothing was queued" from "three of your queued intents timed out".

**Proposed fix:** Add `pendingExpired: Int` to `QueueSnapshot` (QueueStore.kt:15-19), serialize it in `FileQueueStore.replace` (`.put("pending_expired", …)`) and read it in `load()` (defaulting to 0 for an older file); have `sweepExpired` include the new value in the same `persist()` that commits the deletions (move `pendingExpired += expired.size` above the `persist()` call so the counter and the deletion commit atomically), and have `takeExpiredCount()` zero it with a `persist()` as well.

## [P3] [unverified] §16.5 — The universal `scroll_here` attribute is honored only on direct children of `lazy_column`; scrolling `column`/`row` containers and nested descendants ignore it

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/LayoutNodes.kt`:232  
**SPEC line:** None  
**Auditor:** Audit SS16 (UI document model) — SS16.1 node identity and the identity

**SPEC quote:**
> | `scroll_here` | boolean | `false` | Request first-show/index-change scroll anchoring |

**Detail:** The only `scroll_here` reader in the codebase is `RenderLazyColumn`, which scans one level of `children` for the first node with `scroll_here` and calls `listState.scrollToItem(i)` (LayoutNodes.kt:230-241). §16.5 declares the member universal ("The following members MAY appear on any node unless its meaning is nonsensical for that node") and §16.1 lists scroll anchors among the rendering state presentation identity controls. `RenderColumn` and `RenderRow` create real scroll containers via `verticalScroll(rememberScrollState())` / `horizontalScroll(rememberScrollState())` (LayoutNodes.kt:147, 123) — so the attribute is meaningful there — yet neither reads it, and neither keys its `ScrollState` on `ctx.path`. Inside a `lazy_column` the scan is also depth-1 only, so the common pattern of wrapping each row in a `card` hides the marker.

**Failure scenario:** Emacs pushes an agenda view as `{"t":"column","scroll":true,"children":[ …80 `text` rows…, {"t":"text","text":"► now","scroll_here":true}, …20 more… ]}` to anchor the viewport on the current hour. The Companion renders the column scrolled to the top and the marked row is off-screen; the user must hunt for it. The same document authored as a `lazy_column` scrolls correctly, so identical semantics silently depend on the container type. Second case: `{"t":"lazy_column","children":[{"t":"card","children":[{"t":"text","scroll_here":true,...}]}]}` — the marker is on a grandchild, the depth-1 scan at LayoutNodes.kt:234 misses it, and no scroll happens.

**Proposed fix:** Extract the marker scan into a shared helper that walks the child subtree (not just direct children) and returns the top-level index containing it, and use it from `RenderLazyColumn`, `RenderColumn` (when `scroll`) and `RenderRow` (when `scroll`) — for the non-lazy containers translate the index into a `ScrollState.animateScrollTo` against the measured child offset. Key each `rememberScrollState()` on `ctx.path` so the anchor survives a same-identity re-push, and add a `scroll_here` case to `test/smoke-attrs.el`.

## [P3] [unverified] §17.3 — `divider` silently drops both of its declared members, `color` and `thickness`

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt`:160  
**SPEC line:** None  
**Auditor:** Audit SS17.4 through SS17.6 (layout nodes, the scaffold and its slots,

**SPEC quote:**
> | `divider` | — | `color`, `thickness` | … `spacing`, `run_spacing`, `content_padding`, `elevation`, and `thickness` are non-negative `dp` values.

**Detail:** The dispatcher renders `"divider" -> HorizontalDivider(modifier = m)` (Renderer.kt:160), passing neither the node's `color` nor its `thickness`. `m` is `modifier.universal(node)` (Attributes.kt:110-159), which handles only the §16.5 universal attributes — `bg` paints a background box, not the rule's colour, and there is no universal member that maps to `thickness`. NODE_SCHEMA and contract.json both list the two members (Vocabulary.kt:43), and SpecValidator accepts them, so the sender is told they are honoured. `divider` is a Core Node Set type (§16.2), which the Companion MUST implement, and §17 states that every listed optional member has effect when supplied: "Every listed optional member MAY be omitted and then has the stated default or behavior." This is a per-type member gap, not toolkit-appearance latitude under §16.4.

**Failure scenario:** Emacs pushes `{"t":"divider","color":"error","thickness":4}` to mark a destructive section boundary. The Companion renders the default 1dp `outlineVariant` hairline; the authored emphasis (a 4dp error-coloured rule) is invisible and the separator is indistinguishable from every other divider in the document.

**Proposed fix:** Render as `HorizontalDivider(modifier = m, thickness = (safeDp(node.optDouble("thickness", 1.0)) ?: 1f).dp, color = resolveColor(node.optString("color").takeIf { it.isNotEmpty() }) ?: MaterialTheme.colorScheme.outlineVariant)`, mirroring how RenderSurfaceNode resolves `color`/`elevation` (LayoutNodes.kt:204-223).

## [P3] [unverified] §17.3 / §16.4 — A `table` with no data-bearing row renders nothing at all, dropping its `on_add_row`/`on_add_col` affordances

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/LayoutNodes.kt`:489  
**SPEC line:** None  
**Auditor:** Audit SS17.4 through SS17.6 (layout nodes, the scaffold and its slots,

**SPEC quote:**
> | `table` | `rows: TableRow[]` | `aligns`, `on_add_row`, `on_add_col`. Wide tables MAY scroll horizontally. | … “Render” means preserve the declared semantic structure, content, enabled state, interaction hooks, and accessibility meaning.

**Detail:** RenderTable bails out with `if (specs.none { it is CellsSpec && it.cells.isNotEmpty() }) return` (LayoutNodes.kt:489) BEFORE it reads `on_add_row`/`on_add_col` (497-498) and emits the add affordances (504-510). The guard exists to keep the later `maxOf` (496, 544) off an empty collection, but it also discards the two interaction hooks in exactly the state where they are the only way forward. `rows: []` is valid: SpecValidator only requires `rows` to be an array (SpecValidator.kt:641-642) and imposes no minimum, and §17.3 states no non-empty requirement.

**Failure scenario:** Emacs pushes `{"t":"table","rows":[],"on_add_row":{"action":"table.add-row"},"on_add_col":{"action":"table.add-col"}}` for a freshly created empty table. The node renders as a zero-size blank — no "+" affordance — so the user can never add the first row from the Companion, and the surface offers no other path to `table.add-row`.

**Proposed fix:** Move the empty-content guard so it only skips the TableGrid subtree, not the affordances: keep `ncols`/`nrows` at 0 when there is no CellsSpec, render the grid only when one exists, and always emit the AddAffordance rows whose descriptors are present.

## [P3] [unverified] §17.4 — Continuous slider publishes a Float-widened Double that can exceed the authored `max`, and the Companion's own §13.6 check then erases the draft

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/InputNodes.kt`:386  
**SPEC line:** 2037  
**Auditor:** Audit SS17.1 through SS17.3 (the node-type vocabulary preamble, conten

**SPEC quote:**
> For a continuous `slider`, `min` defaults to `0`, `max` to `1`, and `value` to `min`; `min` MUST be less than `max` and `value` MUST be in the closed range.

**Detail:** The continuous branch narrows the authored bounds to Float — `val min = node.optDouble("min",0.0).toFloat()`, `val max = node.optDouble("max",1.0).toFloat()` (InputNodes.kt:377-378) — and then publishes `pos.toDouble()` (lines 386-387), widening the Float back to a Double. For any `max` not exactly representable in binary32 and rounding upward (0.1, 0.2, 0.3, 0.6, …), `max.toFloat().toDouble() > max`: 0.1f widens to 0.10000000149011612. Compose clamps `pos` to `valueRange`, so dragging to the right edge yields exactly that Float. The published value therefore lies outside the authored closed range. Worse, `SurfaceStore.compatible()` re-reads the authored bounds as Doubles and tests `value.toDouble() in min..max` (SurfaceStore.kt:305-307) — so the Companion stores a draft that its own §13.6 compatibility rule classifies as incompatible.

**Failure scenario:** Emacs pushes `{"t":"slider","id":"vol","min":0,"max":0.1,"on_change":{"action":"v.set"}}`. The user drags to the far right. The Companion emits `state.changed {"id":"vol","value":0.10000000149011612}` — above the authored `max` of 0.1 — and stores it as the draft. Emacs then re-pushes the same surface (any unrelated edit, same presentation identity): `reconcileDrafts` calls `compatible()`, which computes `0.10000000149011612 in 0.0..0.1` = false, and the draft is erased at SurfaceStore.kt:281. The user's slider setting is silently discarded and vanishes from the next welcome `input_state`.

**Proposed fix:** Keep the authored bounds as Doubles and quantize the published value back into them: publish `pos.toDouble().coerceIn(minDouble, maxDouble)`, or round-trip through the authored Double bounds (`minD + (maxD - minD) * fraction`) so the emitted value always satisfies the closed-range invariant that `SurfaceStore.compatible()` re-checks.

## [P3] [unverified] §17.7 — needsInput/inputPrompt are escape-blind: an escaped $${input:...} snippet opens a spurious prompt whose value is discarded

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/ToolbarEdits.kt`:85  
**SPEC line:** 2152  
**Auditor:** Audit SS17.7 (editor toolbar: snippets, substitution tokens, placement

**SPEC quote:**
> `$${` MUST produce a literal `${` without beginning a placeholder.

**Detail:** `needsInput` is `snippet.contains("\${input:")` (ToolbarEdits.kt:85) and `inputPrompt` uses `indexOf("\${input:")` (line 77) — both plain substring searches that match inside an escaped `$${input:...}`. EditorToolbar.runOp (EditorToolbar.kt:87) gates the modal on `needsInput`, so an escaped token parks the op in `pendingInput` and shows SnippetInputDialog titled with the escaped token's text. `render` then correctly treats the sequence as a literal (line 45-47) and never consumes the entered value. The user is prompted for a placeholder that, per line 2152, was never begun.

**Failure scenario:** Toolbar item {label:"Doc",snippet:"$${input:Name}"} (valid: SpecValidator counts one match, not >1). Tapping it opens a modal titled 'Name'; the user types 'Alice' and presses OK; applySnippet renders the escape and inserts the literal text '${input:Name}'. 'Alice' is silently dropped and the user is left with a modal that did nothing.

**Proposed fix:** Give ToolbarEdits one escape-aware scanner that returns the first LIVE input token (index + prompt) and implement needsInput/inputPrompt on top of it, so the prompt decision uses the same traversal as render (and, per the §17.7 finding above, the same one the validator's at-most-one count uses).

## [P3] [unverified] §18.3 — Pie-menu descriptors bypass the canonical §14.1 rules — dotless action names and drop+ttl_s/dedupe are accepted and dispatched

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:790  
**SPEC line:** 2263  
**Auditor:** Audit SS18.1 through SS18.3 (dialogs incl. the dialog.show request and

**SPEC quote:**
> `items` is a non-empty array of objects containing `label: string`, a remote ActionDescriptor named `on_tap`, and optional `icon: identifier`. Every action obeys Section 14.

**Detail:** validPieDescriptor (CompanionEngine.kt:790-796) hand-rolls a three-line subset: `action` is a String, `when_offline` defaults/equals "drop", and args do not collide with the injected members. It never applies the rules the reference's own validateAction enforces everywhere else: (a) §14.1 SPEC.md:1231 "An action name MUST contain at least one dot" (SpecValidator.kt:889-890); (b) §14.1 SPEC.md:1238 "`ttl_s` and `dedupe` MUST be absent when `when_offline` is `drop`" (SpecValidator.kt:896-897); (c) §14.2 exactly-one-of action/builtin — a descriptor carrying BOTH `action` and `builtin` passes because only `action` is inspected; (d) `confirm` non-empty. §18.3 requires an invalid menu to be dropped, not shown ("the Companion MUST keep all existing menus unchanged, MUST drop that `pie_menu.show`" for the limit case, and validPieCategories is the only gate for content). PieMenuTest.kt covers the queue-policy and injected-arg-conflict rejections (lines 141-154) but every leaf/nested helper uses a dotted name (lines 54-62), so the dotless branch is untested and unguarded. Raised as W7 finding at docs/AUDIT-w7-conformance.md:279 and still unfixed.

**Failure scenario:** Emacs sends pie_menu.show {menu_id:"capture", categories:[{label:"Todo", on_tap:{action:"nodot"}}]}. The menu is accepted and presented. The user selects the wedge; selectPieMenu (CompanionEngine.kt:804-818) dispatches event.action with action:"nodot". ebp.el's handler requires `(string-search "." action)` (ebp.el:894) and answers -32602 invalid-params (ebp.el:897), so the Companion has emitted a wire-invalid event and the user's tap is lost with an error rather than the menu having been rejected up front. Symmetrically {action:"a.b", when_offline:"drop", ttl_s:60} is displayed though §14.1 makes it content-invalid.

**Proposed fix:** Replace validPieDescriptor with a call into SpecValidator.validateAction using a throwaway Ctx (as the notification path now does), then add the two pie-specific extras on top: force when_offline == drop and reject an args collision with menu_id/category_index/item_index. Also validate the optional `icon` as a §4.4 identifier.

## [P3] [unverified] §18.5 — Notification action PendingIntents are keyed on the action LABEL, so two same-label actions in one notification collapse to one

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/Notifications.kt`:204  
**SPEC line:** 2350  
**Auditor:** Audit SS18.5 (notification surfaces: meta, priority monotonicity amend

**SPEC quote:**
> `actions` is an ordered array. Each entry MUST contain `label` and `on_tap`, and MAY contain `icon`, `dismiss`, and `input`. The platform MAY display fewer actions, so Emacs MUST author the most important first and MUST NOT rely on an icon as the only label.

**Detail:** Notifications.buildAction line 204 computes the PendingIntent request code as `"$surface/$label".hashCode()`. Every action Intent is `Intent(ctx, NotificationActionReceiver::class.java)` with the on_tap carried purely in extras (lines 199-203), and Intent.filterEquals — the equality PendingIntent uses — ignores extras entirely. The request code is therefore the ONLY discriminator between two actions of the same notification. §18.5 imposes no uniqueness requirement on `label`, and SpecValidator.validateNotificationAction (SpecValidator.kt:230-301) enforces none, so two entries with equal labels are a valid authored set. With FLAG_UPDATE_CURRENT (line 210) the second buildAction call rewrites the first PendingIntent's extras in place and both buttons then dispatch the second action's on_tap. This is the same defect class the W8 audit fixed for reminders (P1-6: rid.hashCode -> owner-scoped truncated SHA-256 in Notifications.reminderKey, lines 52-57); the notification-action path was not brought along.

**Failure scenario:** Emacs posts `notification:reminder-1` with meta.actions = [{label:"Snooze", icon:"snooze", on_tap:{action:"agenda.snooze", args:{mins:10}, when_offline:"queue", ttl_s:3600}}, {label:"Snooze", icon:"alarm", on_tap:{action:"agenda.snooze", args:{mins:60}, when_offline:"queue", ttl_s:3600}}]. Both buildAction calls produce rc = "notification:reminder-1/Snooze".hashCode(); the second call's FLAG_UPDATE_CURRENT overwrites the shared PendingIntent's on_tap extra. Tapping the first (10-minute) button queues agenda.snooze {mins:60} — the user's chosen action is silently replaced by a different one.

**Proposed fix:** Key the request code on the action's ordinal INDEX rather than its label — e.g. reuse the collision-resistant helper as reminderKey(surface, "action:$index") (truncated SHA-256 over surface + index) — so distinct entries always get distinct PendingIntents regardless of label text or String.hashCode collisions. Passing the index in the extras also lets the receiver report which entry fired.

## [P3] [unverified] §20.2 — No startup guard binds `device.caps` to the caps this build can validate, so an advertised-but-unvalidated row answers -32602 to a structurally valid request

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CapabilityCatalog.kt`:50  
**SPEC line:** None  
**Auditor:** Audit SS20 (device capability module) against CapabilityCatalog.kt, Co

**SPEC quote:**
> The Companion MUST validate all arguments before beginning side effects. It
MUST NOT treat a string argument as executable code. A capability advertised
by name MUST implement the schema and observable semantics in its registry.

**Detail:** CapabilityCatalog.VALIDATED holds 10 of the SPEC's 18 catalog rows (CapabilityCatalog.kt:50-53); validateArgs' `else ->` branch throws ContentInvalid("cap", "capability not validated by this build") for the other 8 (line 82), and handleCapabilityInvoke maps every ContentInvalid to -32602 (CompanionEngine.kt:1083-1085). Because the 1001 caps-membership gate runs FIRST (line 1078), a cap that IS in config.deviceReport.caps but is not in VALIDATED passes the 1001 gate and then receives -32602 for a perfectly well-formed Args object — an answer §20.2's taxonomy has no case for (the row is advertised, so not 1001; the Args are valid, so not -32602; nothing was attempted, so not 1003). Nothing enforces the invariant: checkLimits (CompanionEngine.kt:1583) validates the limits object and the report's byte size but never inspects `caps`, and CapabilityCatalog's own KDoc concedes the gap in prose ("A Companion advertising a cap in `device.caps` outside this set is misconfigured") rather than in code. This is not purely hypothetical inside the library: buildWelcome contains a first-class branch for a report advertising `state.get` (CompanionEngine.kt:1569-1571, keeping `state_types` non-empty in a capabilities-only session), so the welcome path is written to accommodate exactly a report the invoke path cannot serve. Answering the assignment's direct question: the shipping host advertises only `vibrate` and `clipboard.read` (AppCapabilities.kt:26), both in VALIDATED, so NO capability is currently advertised without full argument validation — the defect is the missing guard, not a live unvalidated row. Reported by the W7 audit (docs/AUDIT-w7-conformance.md:316) and unremediated. Test coverage exists for the throw itself (CapabilityTest.kt:258 asserts `state.get` fails validation) but not for the end-to-end misconfiguration.

**Failure scenario:** A host (this reference's Android app once `apps.list` or `state.get` lands, or any downstream embedder) adds "state.get" to AppCapabilities.CAPS and implements it in its CapabilityHandler, but does not extend CapabilityCatalog. The engine constructs successfully. Emacs reads device.caps, sees state.get, and sends capability.invoke {cap:"state.get", args:{types:["battery.level"]}} — valid per §20.3/§21.7. The engine answers -32602 invalid-params, so an advertised row is permanently unusable and the failure surfaces as a bogus "your arguments are wrong" to the peer rather than as a build-time error.

**Proposed fix:** In checkLimits (or the init block alongside it), add `for (c in jsonStringSet(config.deviceReport, "caps")) require(c in CapabilityCatalog.VALIDATED) { "device.caps advertises $c, which this build cannot validate" }` so a misconfigured host fails fast at construction instead of emitting a taxonomy-violating response at invoke time. Add the same assertion for `trigger_caps` (which must additionally be a subset of `caps` per §20.1, also unchecked today).

## [P3] [unverified] §21.4 — Sensitive-substitution approval is a single blanket boolean, the mechanism §21.4 declares non-conformant

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/TriggerValidator.kt`:23  
**SPEC line:** 3056  
**Auditor:** Audit SS21 (device trigger module) end to end — SS21.1 trigger.set rep

**SPEC quote:**
> This approval is
per (sensitive source type, sink kind) combination and defaults to deny:
approving one combination MUST NOT approve another, and a single blanket
allowance covering all sources or all sinks is non-conformant.

**Detail:** `TriggerCaps.sensitiveSubstitutionApproved: Boolean` (TriggerValidator.kt:23), fed from `CompanionConfig.sensitiveSubstitutionApproved` (CompanionEngine.kt:32) and consumed at TriggerValidator.kt:126-128 as `if (type in SENSITIVE && !caps.sensitiveSubstitutionApproved && Substitution.referencesData(normOnFire)) throw …`, is exactly the "single blanket allowance covering all sources or all sinks" the SPEC names as non-conformant: one flag covers all three sensitive sources (`sms.received`, `call.state`, `calendar.event`) and all sink kinds (notify, cap/TTS, intent, share). `Substitution.referencesData` also collapses sink kind entirely — it returns a single boolean over the whole `on_fire` array without distinguishing which entry is a `notify` versus which is a `{cap,…}`. The reference never sets the flag true (default `false`, and no host code assigns it), so the shipped behavior is always-deny and therefore conformant; the defect is that the only approval mechanism the library exposes is the one the SPEC forbids. The source comment at lines 119-125 acknowledges this.

**Failure scenario:** A host wires an approval UI to this flag. The user approves "calendar title in a local notification" — the only combination they intended. Setting `sensitiveSubstitutionApproved = true` simultaneously authorizes `sms.received` body text into `tts.speak` and `call.state` numbers into `share.send`, because the single flag is the entire gate. §21.4's "approving one combination MUST NOT approve another" is violated by construction, and the user's SMS body is spoken aloud from a trigger they never approved.

**Proposed fix:** Replace the boolean with an approval set, e.g. `approvedSensitiveSinks: Set<Pair<String,String>>` keyed by (sensitive source type, sink kind), where sink kind is derived per `on_fire` entry (`notify` for `{notify:…}`, the capability's declared sink class for `{cap,…}`). Evaluate it per entry in `normOnFire` rather than once over the whole array, so `on_fire:[{notify},{cap:tts.speak}]` on an `sms.received` trigger requires two distinct approvals. Add a TriggerTest asserting approval of (sms.received, notify) does not admit (sms.received, tts.speak).

## [P3] [unverified] §21.5 — `network` and `calendar.event` have no level/baseline path in the runtime, so they cannot honor the silent-baseline MUST

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/TriggerRuntime.kt`:60  
**SPEC line:** 3112  
**Auditor:** Audit SS21 (device trigger module) end to end — SS21.1 trigger.set rep

**SPEC quote:**
> For `power`, `battery.level`, `screen`, `headset`, `airplane`, `state.edge`,
`network`, `wifi.enabled`, `bluetooth.enabled`, `calendar.event`, and
`call.state`, the Companion MUST establish the current state or level silently
when first arming a new or changed registration and when restoring
registrations after a Companion or device restart

**Detail:** `TriggerRuntime.ENUM_FIELD` (lines 60-63) covers `screen`, `power`, `headset`, `airplane`, `call.state`, `wifi.enabled`, `bluetooth.enabled`, and `battery.level` is special-cased. `network` and `calendar.event` — both named in the §21.5 silent-baseline list — appear in neither. Consequently `armBaselines` (74-117) records nothing for them (no `when` branch matches), and `onSample` (126-140) has no branch that can produce a crossing or transition for them, so a registration of either type can only ever be reached through `onExternal`, which (see the separate finding) admits unconditionally and consults no baseline. The types ARE in the validator's closed catalog (`normParams` handles `"network"` at TriggerValidator.kt:180-186 and `"calendar.event"` at 193-200), so they can be registered by any host that advertises them. §21.5 additionally requires `calendar.event` to "avoid duplicate boundary fires" and `network` fire data `{event, transport?}` — neither has any implementing code.

**Failure scenario:** A host advertises `network`. Emacs registers `{"id":"on-wifi","type":"network","params":{"event":"available","transport":"wifi"},"policy":"drop","on_fire":[{"notify":{"text":"on wifi"}}]}`. The Companion's connectivity callback fires its initial sticky `onAvailable` for the already-connected Wi-Fi network at registration time and calls `observeExternal("network", …)`. No baseline was ever established (`armBaselines` has no `network` branch), so the sticky report is admitted and posts a notification — directly violating "A sticky platform report that merely supplies that baseline MUST NOT fire."

**Proposed fix:** Either (a) implement the two types in the runtime: add `network` (track the `{connected, transports}` sample, fire `{event, transport?}` only on a connectivity transition matching the params filter) and `calendar.event` (track the `{ongoing}` level plus per-event boundary identity so a `started`/`ended` boundary is not re-reported), routing both through `onSample` so they get the same silent baseline as the other level types; or (b) if they are deliberately deferred, remove them from `TriggerValidator.normParams` so a set naming them is rejected with 1101, rather than accepted and mishandled.

## [P3] [unverified] §21.5 — The validator refuses `queue`/`wake` for `sms.received`/`call.state` instead of implementing the encryption boundary or declining to advertise the source

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/TriggerValidator.kt`:100  
**SPEC line:** 3168  
**Auditor:** Audit SS21 (device trigger module) end to end — SS21.1 trigger.set rep

**SPEC quote:**
> A queued `sms.received` or `call.state` record's fire data and any
captured sensitive fields MUST be encrypted at rest under a platform
keystore-backed key before the Section 21.2 transaction commits, and be
decryptable only for delivery or deletion; where the platform provides a
keystore-backed facility this is unconditional, and a Companion that cannot meet
it MUST NOT advertise the source in `device.trigger_types`.

**Detail:** §21.5 (amendment #48) offers exactly two conformant postures for a sensitive source: encrypt the queued record at rest under a keystore key, or do not advertise the source at all. The remediation for the prior audit's P2-7 invented a third: `ENCRYPTED_IF_QUEUED = setOf("sms.received", "call.state")` (TriggerValidator.kt:39) with `if (durable && type in ENCRYPTED_IF_QUEUED) throw ContentInvalid("$path.policy", "sensitive type requires policy drop")` (lines 100-101). §21.1's trigger schema places no per-type restriction on `policy`, and §21.5 explicitly contemplates a QUEUED sensitive record (it specifies how such a record must be protected and deleted), so `{"type":"sms.received","policy":"queue","ttl_s":3600}` is a valid entry that the library rejects with 1101. `FileQueueStore` still writes uniform plaintext, so the encryption boundary itself remains unimplemented. On the shipped Android profile this is unreachable — `AppCapabilities.TRIGGER_TYPES` (AppCapabilities.kt:32) advertises neither source, so the `trigger_types` membership check at TriggerValidator.kt:77 fires first, which is the SPEC's own "MUST NOT advertise" remedy — but the wire library is host-agnostic and a host that DOES supply a keystore-backed queue would have its conformant sets rejected.

**Failure scenario:** A downstream host builds on the wire library, implements an `EncryptedFile`-backed `QueueStore`, and advertises `sms.received` in `device.trigger_types` (now conformant per §21.5). Emacs sends `{"id":"otp","type":"sms.received","params":{"from":"+15550100"},"policy":"queue","ttl_s":3600}` — a set the SPEC declares valid. `TriggerValidator.normTrigger` throws at line 101 and the Companion replies `1101 triggers-rejected / "sensitive type requires policy drop"`, refusing an entry §21.5 permits and forcing the author into `drop`, which loses the occurrence whenever no session is READY.

**Proposed fix:** Replace the hard-coded policy refusal with a capability flag on `TriggerCaps` (e.g. `sensitiveQueueEncrypted: Boolean`, default false) that the host sets only when its `QueueStore` is keystore-backed; reject `queue`/`wake` for `SENSITIVE` types only when the flag is false, and document that a host must not advertise the source at all in that configuration. Longer term, add a `sensitive` flag to the queue record and an encryption seam in `DurableQueue`/`FileQueueStore` so the §21.5 boundary is actually implemented.

## [P3] [unverified] §21.7 — `calendar.event` state predicate ignores its `calendar` and `title_contains` fields

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/TriggerRuntime.kt`:335  
**SPEC line:** 3204  
**Auditor:** Audit SS21 (device trigger module) end to end — SS21.1 trigger.set rep

**SPEC quote:**
> | `calendar.event` | `calendar?`, `title_contains?` | A matching event is ongoing now. |

**Detail:** `TriggerValidator.normPredicate` accepts and preserves the predicate's `calendar` and `title_contains` members (TriggerValidator.kt:275-277), but `TriggerRuntime.predicateHolds` evaluates `"calendar.event" -> s.optBoolean("ongoing")` (line 335) — it reads only the unparameterized `{ongoing}` sample from `stateProvider(type)` and discards both filters. §21.7's row requires "A matching event is ongoing now", not "any event is ongoing now". Because §21.7 also says "When `when` is supplied, `holds` MUST be the boolean result of the same evaluator used for trigger gates", the same defect surfaces through `state.get.when`. Latent on the reference Android profile (`state_types` = `["battery.level"]`, AppCapabilities.kt:43) but live for any host advertising `calendar.event`.

**Failure scenario:** A host advertises `calendar.event` in `device.state_types`. Emacs gates a trigger with `when:[{"type":"calendar.event","title_contains":"Standup"}]` so it only fires during standup. A "Lunch" event is ongoing; the platform sample is `{"ongoing":true}`; `predicateHolds` returns true and the gate passes, so the trigger fires during lunch — the gate is silently broadened from "a matching event" to "any authorized event".

**Proposed fix:** Widen the state-provider seam so a parameterized predicate can be evaluated against the platform rather than only against the §21.7 `state.get` sample shape — e.g. change `stateProvider` to `(type: String, predicate: JSONObject?) -> JSONObject?` (null predicate = the plain `state.get` sample), and have `predicateHolds` pass the predicate through for `calendar.event`. Add a TriggerRuntimeTest asserting a `title_contains` predicate does not hold for a non-matching ongoing event.

## [P3] [unverified] §24.3 — ebp.el implements no sender for the three §11 `editor.sync` annotation notifications, so an Emacs endpoint that negotiates editor.sync cannot emit diagnostics.show, eldoc.show, or fontify.show at all

**Location:** `emacs/ebp.el`:557  
**SPEC line:** 3459  
**Auditor:** Audit SS11 (method registry) and SS12 (versioning and compatibility). 

**SPEC quote:**
> An implementation claiming an optional module MUST implement every REQUIRED
method, state transition, type, and failure rule in that module.

**Detail:** §11 registers five Emacs-sender editor.sync methods (SPEC.md:942-947): `edit.resync`, `edit.apply` (requests) and `diagnostics.show`, `eldoc.show`, `fontify.show` (notifications), all §19. ebp.el ships senders for the first two only — `ebp-client-edit-apply` (emacs/ebp.el:1045) and `ebp-client-edit-resync` (:1068) — and grepping ebp.el for `diagnostics`, `eldoc`, or `fontify` returns zero hits anywhere in the 1293-line file. There is no generic escape hatch either: `ebp-client-notify` (:604) is public, but every other Emacs-sender method in §11 has a typed wrapper (toast :1141, theme :1151, reminders :1166, capability.invoke :1187, triggers :1208, pie menu :1228/:1240, dialog :1245), so the three annotation methods are the sole gap in the endpoint's §11 sender surface.

The Companion half is complete and waiting: `handleAnnotation` (CompanionEngine.kt:1317-1330) is wired for all three method names at CompanionEngine.kt:719-720, gates on `editor.sync` at :1319, and enforces the §19.5 session/seq discard rule. §19.5 (SPEC.md:2667-2683) fully specifies the three params shapes, including the normative constraint that fontify runs "MUST be sorted, MUST NOT overlap, and MUST fit the synchronized text" — a sender-side obligation with no sender to carry it. §24.3 additionally warns (SPEC.md:3465-3467) "An implementation MUST NOT advertise `editor.sync` while implementing only completion or only annotations; the editor state machine is one negotiated unit" — ebp.el's editor.sync surface is completion + apply/resync + zero annotations.

**Failure scenario:** An Emacs application negotiates `:wants '("editor.sync")`, the Companion grants it, and a synchronized editor opens (`edit.open` handled at emacs/ebp.el:548-549, shadow tracked in the `editors` table). Flymake produces two diagnostics for the buffer region under sync. There is no ebp.el call that delivers them: no `ebp-client-diagnostics-show`, no `ebp-client-eldoc-show`, no `ebp-client-fontify-show`. The Companion's `handleAnnotation` and `annotationListener` (CompanionEngine.kt:1107, 1317-1330) — and the whole §19.5 receive path built in W7 — are dead code that no conforming Emacs sender in this repo can ever reach, and the on-device editor renders unannotated text for a session whose module was negotiated as one unit.

**Proposed fix:** Add three thin senders next to the existing editor half (after emacs/ebp.el:1085), each looking up the `(document . editor-id)` entry in `ebp-client-editors` for its live `:session`/`:seq` and calling `ebp-client-notify`: `ebp-client-diagnostics-show` (params `{editor_id, session, seq, diagnostics}` with each entry `{start,end,severity,message}`, severity in error/warning/info/hint), `ebp-client-eldoc-show` (`{editor_id, session, seq, text}`), and `ebp-client-fontify-show` (`{editor_id, session, seq, runs}`), with the last asserting §19.5's sorted / non-overlapping / within-length invariant before it sends. Gate all three on `editor.sync` per the capability-gating fix. Add an ERT round-trip covering the §19.5 discard rule (stale `seq` dropped by the Companion).

## [P3] [unverified] §7.4 — ebp.el reference decoder discards already-decoded messages when a later frame in the same feed signals

**Location:** `emacs/ebp.el`:267  
**SPEC line:** 519  
**Auditor:** Audit SS5 (transport profiles) and SS6 (Content-Length framing) agains

**SPEC quote:**
> Each endpoint MUST parse frames in wire order. Each endpoint MUST dispatch session-state transitions, surface mutations, `state.changed`, durable events, and editor-stream operations in receive order within their applicable ordered channel.

**Detail:** `ebp-decoder-feed` accumulates decoded messages in a local `messages` list and returns it (ebp.el:263-270). When a later frame in the same buffer signals — `ebp-parse-error` from `ebp--parse-body`, or `ebp-frame-close` from `ebp--parse-header` on the next header — the signal unwinds out of `ebp-decoder-feed` and `messages` becomes unreachable: the caller receives the condition, never the frames already decoded ahead of the bad one. Verified on Emacs 30.1 against this checkout: feeding one buffer of `"Content-Length: 2\r\n\r\n{}" + "Content-Length: 5\r\n\r\n{nope"` yields only `(ebp-parse-error "{nope")` — the valid `{}` frame is silently dropped. The Kotlin twin deliberately avoids exactly this by handing each message to a consumer callback before the throw (FrameCodec.kt:48-54: "a well-formed frame pipelined ahead of a bad one in the same read is not lost"), so the two decoders that FrameCodec.kt:3 calls twins behave differently on the same bytes. Scoped P3 because the live Emacs path rents jsonrpc.el (SPEC amendment #34) and this decoder is currently exercised only by the §24.5 conformance suite and any future non-jsonrpc transport — but that is precisely the artifact a suite certifies against.

**Failure scenario:** The Companion writes `state.changed` for `(app:main, title)` and, in the same TCP segment, a frame whose body exceeds the 64-container depth limit. A future Emacs transport driven by `ebp-decoder-feed` gets only `ebp-parse-error`; the `state.changed` is dropped with no gap marker and no resync trigger, so Emacs's `input-values` for `(app:main . title)` silently retains the stale value while the Companion believes it was delivered.

**Proposed fix:** Give `ebp-decoder-feed` the Kotlin shape: accept an optional CONSUMER function and call it on each message as it is decoded (or, keeping the return-list API, store the accumulated messages on the decoder struct — e.g. a `pending-messages` slot drained by the caller — before signalling), so decoded frames survive the non-local exit. Add a wire golden pairing a valid frame with a following recoverable-error frame in one fixture.

## [P3] [unverified] §8 — Emacs-side -32603 replies generated by jsonrpc.el carry no `error.data`, so the §8-mandated `data.kind` is missing

**Location:** `emacs/ebp.el`:460  
**SPEC line:** 545  
**Auditor:** Audit SS7 (JSON-RPC 2.0 conventions) and SS8 (error model) in both twi

**SPEC quote:**
> An EBP-defined error MUST use a numeric JSON-RPC `error.code`, a concise
human-readable `error.message`, and an `error.data` object containing the stable
string member `kind`.

**Detail:** ebp.el correctly re-attaches `data` for errors it raises itself: `ebp-client--error` (ebp.el:470-475) stashes `(:kind KIND ...)` on the connection and the `jsonrpc-convert-to-endpoint` override (ebp.el:460-468) `plist-put`s it back onto the reply's `:error` plist. I verified against /usr/share/emacs/30.1/lisp/jsonrpc.el that the default dispatch loop builds `(:error (:code ... :message ...))` and discards `jsonrpc-error-data`, and that the override's mutation sticks because the `:error` value is the same cons shared between `message` and `converted`. But jsonrpc.el has a SECOND error path the override cannot help: its outer `(condition-case ... (error '(:error (:code -32603 :message "Internal error"))))` fires for any non-`jsonrpc-error` Lisp signal escaping a request handler, and in that case no `ebp-client--error` ran, so `ebp--connection-error-data` is nil and the override attaches nothing. The wire frame is then `{"jsonrpc":"2.0","id":N,"error":{"code":-32603,"message":"Internal error"}}` — a code that IS in §8's table (kind `internal-error`) and in contract.json's error_codes, emitted with no `data` at all. ebp.el's own comment at :449-455 names the downstream cost ("SPEC 15.3 degrades `blocked_by` to \"json-rpc-error\" without it") and the Companion does exactly that at CompanionEngine.kt:515-517, reporting a `blocked_by` kind that appears nowhere in §8's taxonomy. The reachable triggers are handlers ebp.el itself funcalls: an application action registered via `ebp-client-register-action` and invoked at ebp.el:905, or the `:edit-complete-function` whose return value ebp.el:1042 passes to `vconcat`.

**Failure scenario:** An allowlisted action handler signals `(wrong-type-argument stringp nil)` while servicing a replayed `event.action` with request id N. jsonrpc.el replies `{"jsonrpc":"2.0","id":N,"error":{"code":-32603,"message":"Internal error"}}` with no `data`, violating §8's MUST. `onPumpResult` pauses the pump and `concludeReplay` returns `blocked_by: "json-rpc-error"` instead of `"internal-error"`, so Emacs's replay-retry logic and any operator diagnostic see a kind outside the error taxonomy.

**Proposed fix:** Close the fail-open path at its source rather than at the encoder: wrap the handler funcall in `ebp-client--request-dispatcher` (ebp.el:778) in `(condition-case err ... (jsonrpc-error (signal (car err) (cdr err))) (error (ebp-client--error client -32603 "Internal error" "internal-error")))` so every non-jsonrpc signal becomes a properly-kinded EBP error before jsonrpc.el's generic branch sees it. Belt-and-braces: make the override at ebp.el:466-467 default `data` to `(:kind "internal-error")` whenever a reply's `:error` has code -32603 and no stashed data.

## [P3] [unverified] §9.1 — Emacs endpoint offers no local pairing removal: the durable EventId receipt store can never be erased

**Location:** `emacs/ebp.el`:813  
**SPEC line:** 615  
**Auditor:** Audit SS9 (pairing and mutual authentication) against companion/wire/A

**SPEC quote:**
> The Emacs endpoint MUST likewise provide local removal of a pairing and erase its token and EventId receipt records when the user invokes it.

**Detail:** `ebp.el` owns a durable receipt store: `ebp-receipt-file` (line 33), opened and pruned by `ebp-client--receipts-load` (line 813) and written by `ebp-client--receipt-commit` (line 847), backed by SQLite when available and an append-only text file otherwise. There is no counterpart erase: no interactive command, no `ebp-forget-pairing`, no exported function that drops the `receipts` table / deletes the file and clears the in-memory `(ebp-client-receipts client)` hash. `ebp-client-close` (line 569) only calls `sqlite-close`. The token half is arguably the caller's (it arrives as the `:token` config plist member and ebp.el never persists it), but the receipt half is unambiguously this endpoint's own storage and there is no API to erase it.

**Failure scenario:** A user unpairs a phone and re-pairs it (a new pairing ID, per §9.1 "Re-pairing creates a new pairing ID and an empty state partition"). On the Emacs side every EventId observed under the old pairing remains in ~/.emacs.d/ebp-receipts for the full `ebp-receipt-retention-seconds` (7 days). Removing the pairing through any application-level UI cannot erase them because ebp.el exposes no function to do so; the user must know to delete the file by hand.

**Proposed fix:** Add an autoloaded `ebp-forget-pairing` (interactive) that, for a given `:receipt-file`, closes any open sqlite handle, executes `DELETE FROM receipts` (or deletes the plain file), clears `(ebp-client-receipts client)`, and documents the §9.1 limitation that it cannot erase the peer's storage. Cite §9.1 in its docstring alongside the existing §14.4 citation.

## [P3] [unverified] §9.2 — An absent or wrong-typed `protocol` in session.hello is answered 1202 protocol-version instead of -32602

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1472  
**SPEC line:** 650  
**Auditor:** Audit SS9 (pairing and mutual authentication) against companion/wire/A

**SPEC quote:**
> A protocol mismatch MUST receive `1202 protocol-version`; another invalid hello field MUST receive `-32602`.

**Detail:** `handleHello` reads `val protocol = params.opt("protocol")` (line 1471) and branches on `if (protocol != 2)` (line 1472) before any type or presence check, returning 1202 with `data.supported = [2]`. `opt` yields `null` when the member is absent and a `String` when it is `"2"`, so both an omitted required member and a member that fails the table's declared type `integer` are reported as a protocol-major mismatch rather than as an invalid hello field. The §9.2 params table marks `protocol` Required=yes / Type=integer; a value that is not an integer has no major to mismatch, and an absent required member is "another invalid hello field". contract.json lists both 1202 and -32602 for `session.hello` and does not disambiguate.

**Failure scenario:** An Emacs-side client (or a third-party endpoint whose JSON writer stringifies numbers) sends `{"protocol":"2","client":{…},"pairing_id":…,"client_nonce":…,"wants":[]}`. The Companion answers `1202 Unsupported protocol major` with `data.supported:[2]`. Per §12 that tells the client the Companion speaks only major 2 — which the client also speaks — so a client implementing version negotiation concludes there is no common major and permanently refuses to reconnect, instead of receiving the -32602 that would identify a malformed request.

**Proposed fix:** In `handleHello`, check presence and type first: `val protocol = params.opt("protocol"); if (protocol !is Int && protocol !is Long) return respondError(id, -32602, "Invalid params", "invalid-params")`, and only then `if (protocol.toLong() != 2L)` return 1202 with `data.supported`. Add engine tests for absent `protocol` and `"protocol": "2"` both expecting -32602.

---

# SPEC findings (78)

## [P1] [unverified] §10.3 — §10.3's READY flush rewrites `revision_seen` to the current revision, which §14.6 explicitly forbids

**SPEC line:** 889  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 1 thr

**SPEC quote:**
> The Companion MUST then clear the surface-disconnection staleness timer and MUST
immediately flush as ordered `state.changed` notifications every divergent
non-password value changed after the welcome snapshot or during `SYNCING`,
using the accepted revision currently shown, even when no event is pending.

**Detail:** §14.6's reconciliation rules say the opposite for the same notification (lines 1486-1488): "`revision_seen` MUST equal the revision of the accepted snapshot presented to the user when the edit was made. The Companion MUST NOT rewrite a pending notification's `revision_seen` after accepting a newer snapshot." §14.5 reinforces the same principle for events (line 1450): "It MUST NOT fabricate the latest revision after the fact; the field records what the user actually saw." The two rules collide whenever the surface's revision changes between the edit and the READY-entry flush — which is not an exotic case but the NORMAL case, because §10.3 step 3 requires Emacs to "send required surface updates or removals using revisions above the reported floors" during SYNCING, i.e. before the flush. Reading (a) (§10.3 literal): report the current revision. Reading (b) (§14.6 literal): report the revision the user actually saw. The reference implementation takes (a) — CompanionEngine.kt:424 uses `surfaces.revisionOf(surface)` at flush time — so the divergence is not hypothetical.

**Failure scenario:** While disconnected, the user edits `title` on `app:main` showing revision 41. On reconnect the welcome reports revision 41; during SYNCING Emacs pushes revision 42 which names nothing in `reset_input_ids`; then `session.ready`. Companion A flushes {surface:"app:main", revision_seen:42, id:"title", value:"offline draft"}; Companion B flushes revision_seen:41. Emacs's §14.6 bullet-3 reconciliation is keyed on `revision_seen` ("no accepted snapshot with a revision greater than `revision_seen` named that ID in `reset_input_ids`"), so an Emacs application that pushed a reset at revision 42 in a later session, or that compares revision_seen against its own pushed revision to decide whether the draft predates its own edit, reaches opposite conclusions about whether to adopt the user's offline text — silently keeping or silently dropping it.

**Proposed fix:** Amend §10.3: replace "using the accepted revision currently shown" with "each notification carrying the `revision_seen` required by Section 14.6 — the revision of the accepted snapshot that was presented when that value was changed, which for a value changed while disconnected is the revision reported for that surface in this session's welcome — never the revision currently shown." Cross-reference §14.5/§14.6 so the no-fabrication principle reads identically in all three places.

## [P1] [unverified] §13.4 — §13.4 defines no SurfaceSpec variant for the `tile:*` namespace registered by amendment #39

**SPEC line:** 1091  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 1 thr

**SPEC quote:**
> The namespace determines the exact SurfaceSpec variant:

| Namespace | Schema |
|---|---|
| `app:*` | One root Node or the multi-view object below |
| `notification:*` | `{body: Node, meta?}` from Section 18.5; multi-view is prohibited |
| `widget:*` | `{title: string, body: Node, empty?: Node, header_action?: ActionDescriptor}`; multi-view is prohibited |

**Detail:** Amendment #39 registered `tile:<name>` in §13.1 (line 997), added `tile` to §10.2's applicable-target and profile-required clauses (lines 845, 854), and registered `surfaces.tile` in §22.1 (line 3262) — but §13.4, the section that decides what `spec` may contain, was not amended, and §13.7 still says (line 1199) "Section 13.4 defines the notification and widget wrappers." The whole of §13.4 is therefore silent on `tile:*`: whether the spec is a bare root Node, a widget-style wrapper, or something with tile-specific state (label/subtitle/active); whether multi-view is prohibited as it is for the other two non-app namespaces; and whether a tile may carry stateful nodes and hence input drafts and welcome `input_state` entries. This also breaks §22.1's own registry rule (lines 3277-3279): "Adding a capability to this registry MUST define all associated methods, objects, limits, failure behavior, and security properties. A capability name MUST NOT be granted as a promise of unspecified best effort." `surfaces.tile` is granted with no object definition. There is likewise no `max_tiles` row in §4.5 even though host tile slots are a bounded platform resource.

**Failure scenario:** With `surfaces.tile` granted, Emacs sends surface.update {surface:"tile:battery", revision:1, spec:{"t":"text","text":"88%"}}. Companion A (app-like reading) applies it. Companion B (widget-like reading) returns 1201 content-invalid because `title`/`body` are missing. Companion C (the reference implementation, SurfaceStore.kt:11, whose SURFACE_ID regex is `(app|notification|widget):...`) returns 1201 with data.reason "surface-id" — it cannot accept ANY tile surface, so a capability it may advertise is unusable. All three pass validate.py, which has no tile fixture.

**Proposed fix:** Amend §13.4: add a `tile:*` row. Smallest coherent choice is to reuse the widget wrapper — `{title: string, body: Node, empty?: Node, header_action?: ActionDescriptor}`; multi-view is prohibited — or, if tiles need platform tile semantics, define a dedicated `{label: string, state?: "active"|"inactive"|"unavailable", subtitle?: string, icon?: string, on_tap?: ActionDescriptor}` object. State explicitly whether a tile spec may contain stateful nodes (recommend: MUST NOT, like `notification:*`, so tiles never produce drafts or `input_state`). Update §13.7's sentence to name the tile wrapper, and add a `max_tiles` row to §4.5 REQUIRED when `surfaces.tile` is granted.

## [P1] [unverified] §15.3 (with §14.4, §7.3) — §15.3 has no permanent-error disposition: any well-formed JSON-RPC error wedges the durable queue forever

**SPEC line:** 1616  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 14 th

**SPEC quote:**
> Any well-formed JSON-RPC error response, including `1500 event-retry` and
`1301 request-cancelled`, MUST stop replay and retain that event and every later
event.

**Detail:** §15.3:1616-1618 lumps EVERY well-formed JSON-RPC error into one disposition — stop, retain the head, retain every later event — with `blocked_by` set to the error's `data.kind` (§15.3:1631-1633). The enumerated examples (`1500 event-retry`, `1301 request-cancelled`) are both transient, but the rule's scope is "any". Meanwhile §7.3:513 makes `-32602 invalid-params` MANDATORY for structurally invalid request params, and `event.action` is a request; §8 also defines the permanent classes `-32601`, `-32603`, `1200`, `1204`. §14.4:1399-1401 says Emacs "MUST return exactly one of" four statuses, of which `rejected` means "permanently invalid" and deletes the record — but §14.4's four-status rule and §7.3's `-32602` mandate collide for an envelope-level defect, and the SPEC never says which wins nor what the Companion does with a permanently-failing head. §15.3:1637 then forecloses the only workaround: "A stopped replay does not permit a later durable event to overtake the retained head." There is no retry bound, no attempt counter, no poison-message rule, and no protocol operation to clear the queue (§23.3 mentions "explicit queue clearing" as a deletion trigger but never defines it as an EBP method). The reference Emacs endpoint takes exactly the path that triggers this: /home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-2/emacs/ebp.el:897 returns `-32602` for an event whose `event_id`/`occurred_at_ms`/context envelope fails validation, and :917 returns `-32603` when a handler returns an unexpected value.

**Failure scenario:** A `queue` event is durably committed by Companion build N whose `occurred_at_ms` serializer emits `1784700000000.0`. Build N+1 replays it after reconnect. Emacs (`ebp-client--handle-event-action`, ebp.el:895-897) sees `(integerp :occurred_at_ms)` fail and returns `-32602 invalid-params` — required by §7.3. Per §15.3 the Companion MUST retain that event and every later event. `queue.replay` now returns `{"delivered":0,"rejected":0,"expired":0,"remaining":N,"blocked_by":"invalid-params"}` on every attempt, forever; §15.3:1637 forbids later valid events from overtaking it, so every subsequently queued action for that pairing is permanently undeliverable. Two conforming Companions diverge: one obeys §15.3 literally and wedges; one treats a permanent JSON-RPC error class as equivalent to `rejected`, deletes the head, and drains — silently discarding user intent that §15.3 says must be retained.

**Proposed fix:** Amend §15.3 to partition error responses by permanence. (1) State that a `1500 event-retry` or `1301 request-cancelled` error, or any error the Companion cannot classify, is TRANSIENT: stop replay, retain the head and all later events, set `blocked_by`. (2) State that `-32600`, `-32601`, `-32602`, `-32603`, `1200`, `1201`, and `1204` in response to an `event.action` are PERMANENT for that record: the Companion MUST delete that durable record, surface a local diagnostic naming the code (parallel to the `rejected` status disposition in §14.4), count it in the replay summary's `rejected`, and CONTINUE with the next `queue_seq` rather than pinning the head. (3) Add a bounded escape for any remaining case: after a Companion-chosen bounded number of delivery attempts of one `event_id` across sessions, the record MUST be discarded with a visible diagnostic rather than block the queue indefinitely, and the bound MUST be documented. (4) Amend §14.4 to acknowledge that §7.3's `-32602` may replace the four-status result for an envelope-level defect and to state that Emacs SHOULD prefer `{status:"rejected"}` over `-32602` whenever the envelope parses, so the durable record is deleted rather than retried.

## [P1] [unverified] §21.3 / §21.7 (with §20.1) — §21.3 vs §21.7: whether `time.window` belongs in `device.state_types` is undefined, and the literal reading makes every time-window gate unauthorable

**SPEC line:** 3004  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 14 th

**SPEC quote:**
> Emacs MUST include a gate only when every predicate type appears in
`device.state_types`. If any type is absent, Emacs MUST omit the entire trigger;
it MUST NOT remove the unsupported predicate and install a weaker trigger.

**Detail:** §21.7:3192-3206 defines `time.window` as a state predicate usable in `when`, and §21.7:3237-3239 confirms "Parameterized `time.window` predicates are valid only inside `when` and do not create a `states` entry." But §21.3:3004-3006 conditions EVERY gate on its predicate types appearing in `device.state_types`, and §20.1:2722 defines `state_types` as "array of distinct state-type identifiers; REQUIRED when `triggers` is granted or `state.get` is in `caps`" with no carve-out. The SPEC never says whether a Companion advertises `time.window` in `state_types`. §21.7:3232-3233's phrasing ("`state.get.types` is an array of distinct advertised state-type names other than `time.window`") only makes sense if `time.window` IS an advertised state-type name — yet §21.7's sample-object table (3211-3222) has no `time.window` row, and §20.1 defines `trackable_state_types` as "array of distinct values from `state_types`", which under that reading would let a conforming Companion list `time.window` as trackable and admit a `state.edge` trigger over a civil-time window whose level semantics are nowhere defined. The reference implementation had to invent past this: /home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-2/companion/wire/src/main/kotlin/com/calebc42/ebp/wire/TriggerValidator.kt:249-253 special-cases `time.window` with an `allowTimeWindow` flag exempting it from the advertised-types check, and contract.json invented a registry the SPEC never authors — `predicate_only_state_types: ["time.window"]` — which §2.2 forbids ("The generator of `contract.json` MUST derive it from this specification's authored definitions").

**Failure scenario:** Emacs authors `{"id":"night-dim","type":"screen","params":{"state":"off"},"when":[{"type":"time.window","after":"22:00","before":"06:00"}]}`. Companion A reads §21.3 symmetrically and rejects the whole replace-set with `1101 triggers-rejected` because `time.window` is absent from the `state_types` it advertised — and a strictly conforming Emacs, applying §21.3's sender rule, would never have sent the trigger at all, so the entire time-gating feature is dead. Companion B (the reference) exempts `time.window` and accepts. Companion C advertises `time.window` inside `state_types`, which then makes it a legal member of `trackable_state_types`, so `{"type":"state.edge","params":{"when":[{"type":"time.window",...}]}}` is admissible with no defined baseline or edge semantics. Three conforming implementations, three incompatible outcomes for the same registration.

**Proposed fix:** Amend §21.7 to name `time.window` explicitly as a PREDICATE-ONLY state type and give it its own advertisement rule: (a) `time.window` is always available in a `when` gate and in `state.get.when` whenever `triggers` (or `state.get`) is granted — it requires no platform permission and no advertisement; (b) it MUST NOT appear in `device.state_types`, `device.trackable_state_types`, or `state.get.types`, and MUST NOT be used as a `state.edge` tracked level; (c) amend §21.3:3004 to read "every predicate type other than the predicate-only types named in §21.7". Then author the predicate-only set in the SPEC so contract.json's `predicate_only_state_types` becomes a derived projection rather than an invented registry (§2.2, §24.4). Simplify §21.7:3232's "other than `time.window`" to a cross-reference to that set.

## [P1] [unverified] §22.1 (with §13.4, §10.2) — §22.1 registers `surfaces.tile` but no section defines the `tile:*` SurfaceSpec shape, so tile updates are unimplementable

**SPEC line:** 3277  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 14 th

**SPEC quote:**
> Adding a capability to this registry MUST define all associated methods,
objects, limits, failure behavior, and security properties. A capability name
MUST NOT be granted as a promise of unspecified best effort.

**Detail:** Amendment #39 added `tile:<name>` as a first-class namespace: §13.1:997 registers the ID pattern, §10.2:845 makes a `tile` surface profile REQUIRED when the capability is granted, §10.2:854 names `tile` as the applicable target for `tile:*`, and §22.1:3262 registers `surfaces.tile`. But §13.4 — "Surface specification shapes", whose opening sentence at 1091 is "The namespace determines the exact SurfaceSpec variant:" — still lists only three rows (`app:*`, `notification:*`, `widget:*`) and closes at 1100-1101 with "Any other combination MUST receive `1201 content-invalid`." No section anywhere states what `spec` must contain for a `tile:*` surface: whether it is a bare root Node like `app:*`, a `{title, body, empty?, header_action?}` wrapper like `widget:*`, whether multi-view is permitted or prohibited, whether a tile carries its own label/state metadata (a Quick-Settings tile slot has an inherent label and on/off state), or whether §13.7's widget-`empty` rule applies. §22.1:3277-3279's own MUST — that adding a registry capability MUST define all associated objects — is therefore violated by the SPEC itself. `contract.json` likewise carries `surfaces.tile` in `capabilities` (line 910) with no tile spec shape, so the projection cannot be derived (§24.4).

**Failure scenario:** A Companion grants `surfaces.tile` and publishes a `tile` profile. Emacs sends `surface.update {"surface":"tile:agenda","revision":1,"spec":{"t":"text","text":"3 due"}}`. Companion A, generalizing from `app:*`, accepts a bare root Node and returns `{"status":"applied",...}`. Companion B, generalizing from the other two non-fullscreen namespaces (`notification`/`widget`, both wrappers), requires `{title, body}` and returns `1201 content-invalid`. Companion C reads §13.4:1100-1101 literally — `tile:*` is not one of the three defined variants, so it is "any other combination" — and rejects every tile update with `1201` regardless of content, making the granted capability permanently unusable. All three are defensible readings of the current text; no Emacs can write a portable tile.

**Proposed fix:** Add a `tile:*` row to §13.4's variant table and its supporting prose. Recommended (parallel to widget, matching the Quick-Settings slot model): `tile:*` uses `{label: string, body?: Node, state?: "active"|"inactive"|"unavailable", icon?: identifier, on_tap?: ActionDescriptor}`; multi-view is prohibited; `stale_spec` uses the same variant; `current_view` is invalid. Add a §13.7 sentence covering tile metadata parallel to the widget `empty`/`header_action` rules, state which limits apply, and project the shape into `contract.json`. If a tile is instead intended to be a bare root Node, say so explicitly in the table rather than leaving it to inference.

## [P1] [unverified] §4.2 — §4.2 still declares request IDs string-only, flatly contradicting amended §7.2 (integer IDs)

**SPEC line:** 142  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 1 thr

**SPEC quote:**
> EBP request IDs are strings; Section 7.2 prohibits numeric request IDs.

**Detail:** Amendment #34 rewrote §7.2 to read (line 487-489) "A request ID MUST be either a JSON string or a JSON integer. A string ID MUST be an identifier under Section 4.4 of at most 64 ASCII octets and MUST NOT be empty. An integer ID MUST be a safe integer under Section 4.2." and added "A host JSON-RPC library that allocates sequential integer IDs per connection — such as core Emacs `jsonrpc.el` — therefore conforms without adaptation." The amendment's §4.2 sentence was never edited, so the normative document now asserts both that numeric IDs are prohibited (§4.2) and that they are legal (§7.2). §2.2 makes SPEC.md the authority over contract.json and goldens, so an implementer cannot resolve the conflict by consulting the derived artifacts (validate.py:251 already accepts str|int, goldens/wire has an integer-id frame). The two divergent readings are: (a) §4.2 is the general rule and §7.2's integer clause is an editorial mistake -> a receiver MUST answer any integer-id request with -32600; (b) §7.2 is the specific, later rule and §4.2 is stale -> integer ids are legal.

**Failure scenario:** An Emacs endpoint renting core jsonrpc.el sends {"jsonrpc":"2.0","id":1,"method":"session.hello",...}. Companion A (reading (b), the reference) proceeds. Companion B (reading (a)) answers -32600 invalid-request for the hello, and because the id-type check precedes state dispatch, EVERY request from that Emacs endpoint fails: the pairing can never authenticate at all, while both implementations pass validate.py.

**Proposed fix:** Amend §4.2: replace the sentence with "EBP request IDs are a JSON string or a safe integer; Section 7.2 states the complete rule and prohibits `null` and fractional numbers." Add the correction to SPEC-CHANGES.md as a follow-on to amendment #34 (no contract or golden change; validate.py already implements the amended rule).

## [P2] [unverified] SS14.6 — SS10.3 and SS14.6 give contradictory revision_seen values for a draft edited during SYNCING that survives a step-3 surface.update

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:424  
**SPEC line:** 1486  
**Auditor:** Audit SS14.4 through SS14.6 (the event.action request protocol, EventI

**SPEC quote:**
> - `revision_seen` MUST equal the revision of the accepted snapshot presented to the user when the edit was made. The Companion MUST NOT rewrite a pending notification's `revision_seen` after accepting a newer snapshot.

**Detail:** SS10.3 (SPEC.md:889-892) says the Companion on entering READY 'MUST immediately flush as ordered `state.changed` notifications every divergent non-password value changed after the welcome snapshot or during `SYNCING`, using the accepted revision currently shown, even when no event is pending.' SS14.6's first reconciliation bullet says the opposite for the same notification: revision_seen MUST equal the revision shown when the edit was made and MUST NOT be rewritten after a newer snapshot is accepted. Both rules govern one concrete object — a value edited during SYNCING at the cached revision, whose surface Emacs then re-pushes at a higher revision in step 3. The reference implementation resolves the conflict in SS10.3's favour: the READY flush reads `surfaces.revisionOf(surface)` (CompanionEngine.kt:424), i.e. the newest accepted revision, not the revision the edit was made against (which is never recorded — syncingDirty holds only (surface, id) pairs, CompanionEngine.kt:345). A different implementer reading SS14.6 first would stamp the older revision. The choice is observable, because Emacs's reset-history reconciliation (ebp.el:932-938) discards a report whose revision_seen is below a revision that named the ID in reset_input_ids and adopts one at or above it.

**Failure scenario:** Welcome reports app:main at revision 5 (cached and on screen). During SYNCING the user edits `title` to "x". Emacs step 3 pushes app:main revision 9 whose title node authors a different value and lists some other id in reset_input_ids; the draft survives SS13.6 reconciliation. At session.ready the Companion flushes state.changed. Implementation A sends revision_seen 9 (SS10.3, what this code does); implementation B sends 5 (SS14.6). If revision 9 had instead named `title` in reset_input_ids, A's report would still be discarded by ebp.el, but for any Emacs that reconciles on '> revision_seen' semantics the two encodings select different winners for the same user keystroke.

**Proposed fix:** Amend SS14.6's first bullet to carve out the SS10.3 flush explicitly, e.g. append: 'except the SS10.3 flush on entering READY, which uses the accepted revision currently shown because the pre-READY snapshot the edit was made against is no longer addressable'; or, conversely, amend SS10.3 to require the edit-time revision and require the Companion to retain it per pending value. Either way one of the two sentences must name the other.

## [P2] [unverified] SS14.6 — SS14.6 states the password/offline-policy rule as an authoring MUST but never gives the Companion a rejection duty, so a non-conforming descriptor has no defined disposition

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:879  
**SPEC line:** 1518  
**Auditor:** Audit SS14.4 through SS14.6 (the event.action request protocol, EventI

**SPEC quote:**
> A remote descriptor that captures a password MUST use `when_offline: "drop"`, MUST NOT use `dedupe` or `ttl_s`, and MUST NOT create an event unless an authenticated `READY` session exists.

**Detail:** Every other cross-member rule about capture_fields is paired with an explicit Companion rejection duty — SS14.1: 'The Companion MUST reject the containing document when a name is absent, duplicated, or non-stateful'; SS14.2: 'The Companion MUST reject the containing document atomically when a descriptor contains both variants, neither variant, a remote-only member on a builtin, an unknown builtin, or invalid builtin parameters.' The password/policy rule at SS14.6 has no such pairing, and SS14.4/SS15.1 do not say what a Companion does when it nevertheless receives one. Three readings are permitted: (a) reject the containing document with 1201 at accept time, (b) accept the document but refuse the occurrence at dispatch with a local diagnostic, (c) trust the descriptor and admit durably (what SpecValidator.validateAction, SpecValidator.kt:879-955, effectively does today, because it never inspects the node's `password` member). Reading (c) is a direct security regression yet no sentence names it as a violation of a Companion MUST other than by inference from the later 'MUST NOT appear in ... a retry queue' sentence.

**Failure scenario:** Two conforming-by-their-own-reading Companions receive the same surface: {t:text_input,id:pw,password:true,on_submit:{action:auth.login,when_offline:queue,ttl_s:600,capture_fields:[pw]}}. Companion A answers surface.update with 1201 content-invalid and shows nothing; Companion B renders the login form and, when the user submits offline, writes the password into its durable queue. Both cite SS14.6. Emacs cannot tell which behavior to expect and cannot distinguish 'my surface was rejected' from 'my secret is on disk'.

**Proposed fix:** Add to SS14.1's capture_fields paragraph (or as a new sentence right after the SS14.6 rule): 'The Companion MUST reject the containing document when a descriptor that would capture a password node — through `capture_fields` or through a password `text_input`'s own submitting hook — sets `when_offline` to `queue` or `wake`, or carries `dedupe` or `ttl_s`. It MUST NOT create, persist, or transmit such an occurrence.' Also state the dispatch-time fallback: a password occurrence attempted outside an authenticated READY session MUST be abandoned with a local diagnostic and immediate erasure.

## [P2] [unverified] §10.1 — §10.1 never defines which handshake failures constitute "a failed handshake", leaving unbounded session.hello retry on one connection

**SPEC line:** 755  
**Auditor:** Audit SS10 (session lifecycle and negotiation) — states, the welcome m

**SPEC quote:**
> A legal handshake method with malformed params MUST receive `-32602`. [...] A failed handshake MUST NOT be retried on the same connection.

**Detail:** §9.3 is explicit for `auth.response`: "A request that fails the declared JSON type, length, or character grammar MUST receive `-32602` followed by connection close" and a bad proof gets "`1203` followed by connection close". §9.2 and §10.1 prescribe the error codes for a bad `session.hello` (`1202 protocol-version` for a wrong major, `-32602` for another invalid field) but prescribe no close and no state change, and §10.1's states table only says CONNECTED permits `session.hello`. An implementer must therefore invent an answer to: is an errored `session.hello` "a failed handshake"? Reading (i) — no, the connection stays in CONNECTED and a corrected hello is legal, which is what the reference does (CompanionEngine.handleHello, CompanionEngine.kt:1470-1502, returns respondError and leaves `state == SessionState.CONNECTED`, so an unlimited number of malformed or wrong-major hellos may be sent on one connection). Reading (ii) — yes, any handshake-method error is a failed handshake and the connection MUST close, matching §9.3's treatment of auth.response. The two readings are observably different on the wire and the choice is security-relevant: §9.1's rate-limit MUST is scoped to "failed proofs per pairing ID and source process or connection" and says nothing about failed hellos, and §10.1's handshake deadline is only a MAY ("Either endpoint MAY close an incomplete handshake after a finite local timeout"), so under reading (i) an unauthenticated peer can hold the single session the `android-loopback-tcp` profile permits (§5.2) indefinitely by looping bad hellos, with no normative bound on attempts.

**Failure scenario:** A local process connects to 127.0.0.1:8765 and repeatedly sends `{"method":"session.hello","params":{"protocol":3,...}}`. Companion A (reading i, the reference) answers 1202 each time and keeps the connection in CONNECTED forever — the socket is held, the profile's one-session slot is occupied, and no rate limit applies because no proof was ever attempted. Companion B (reading ii) closes after the first 1202. A conformance suite written against either behavior fails the other, and Emacs cannot know whether to retry a corrected hello on the same connection or redial.

**Proposed fix:** Amend §10.1 to define "a failed handshake" explicitly, e.g.: "A handshake fails when any `session.hello` or `auth.response` request receives an error response. The Companion MUST close the connection after emitting that error, in `CONNECTED` as in `CHALLENGED`; Emacs MUST redial rather than resend on the same connection." If unbounded hello retry is intended instead, say so and extend §9.1's rate limit to cover failed `session.hello` attempts per source connection with a stated bound, and make the §10.1 handshake deadline a MUST rather than a MAY.

## [P2] [unverified] §10.2 — §10.2 never says whether an authored (never-edited) stateful value belongs to `input_state`, and nothing enforces the aggregate budget against authored values

**SPEC line:** 822  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 1 thr

**SPEC quote:**
> | `input_state` | object mapping present Surface IDs to objects mapping stateful node IDs to their latest non-password JSON values |

**Detail:** "their latest non-password JSON values" does not say whether a stateful node the user never touched contributes its Emacs-authored value. §14.6 line 1511 ("While disconnected, the Companion MUST retain only the latest value per surface and widget ID for welcome `input_state`") is equally neutral, and §13.6 line 1188 ("Emacs SHOULD reflect welcome `input_state` values in its first synchronized surface push") only makes sense under the drafts-only reading. The gap matters because the only enforcement point the SPEC gives for the aggregate cap is scoped to user input: "Before accepting a non-password user change that would enlarge retained input state beyond that aggregate limit, the Companion MUST refuse the change, preserve the preceding logical and native value, and show a local validation diagnostic" (lines 828-831). Under the all-current-values reading there is no defined refusal at all for growth caused by an accepted `surface.update` — §13.2 and §16.1 list no input-state budget among the 1201 rejection reasons — yet §4.5's welcome reservation (`B + limits.max_input_state_bytes - 2 <= limits.max_frame_bytes`) assumes `input_state` can never exceed `max_input_state_bytes`. The reference reads it as drafts-only (SurfaceStore.kt:236-246 iterates `drafts`), which is one of the two readings, not a resolution.

**Failure scenario:** A Companion advertises max_field_bytes 65536, max_input_state_bytes 262144, max_surfaces 16. Emacs pushes 16 `app:*` surfaces, each with 4 `text_input` nodes carrying 65,000-octet authored values. Every snapshot is individually valid (no node exceeds max_field_bytes; node counts are far under 10,000), so every update returns `applied`. Companion B (all-current-values) now owes an `input_state` of about 4.16 MB: its next welcome exceeds max_input_state_bytes, and with the rest of the welcome exceeds max_frame_bytes = 4194304, so the peer MUST close the connection on the oversized declaration (§6.2). Because surfaces and drafts persist across restarts, the pairing is permanently unable to complete a handshake with no recovery short of revocation. Companion A (drafts-only) reports `input_state` omitted and works normally.

**Proposed fix:** Amend §10.2's `input_state` row and prose: "`input_state` carries only values that diverge from the last value Emacs authored for that node — the retained dirty drafts of Section 13.6. A value the Companion holds solely because Emacs authored it MUST NOT appear." Independently, close the enforcement hole in §13.2: "An update whose acceptance would push the pairing's retained input state past `max_input_state_bytes` MUST be rejected with `1201 content-invalid` and `data.reason: \"input-state-limit\"`, leaving the previous snapshot unchanged."

## [P2] [unverified] §11 — §11 assigns every method a capability gate but no section defines the error a Companion returns when that capability was not granted; -32601 and 1001 are both defensible readings

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:870  
**SPEC line:** 932  
**Auditor:** Audit SS11 (method registry) and SS12 (versioning and compatibility). 

**SPEC quote:**
> | `dialog.show` | Emacs | request | R | `surfaces.dialog` | 18 |
...
| `capability.invoke` | Emacs | request | R | `capabilities` | 20 |
| `triggers.set` | Emacs | request | S, R | `triggers` | 21 |

**Detail:** §11's Capability column is normative, and §10.2 (SPEC.md:840-843) forbids Emacs to invoke an ungranted capability-gated method — but nothing anywhere states what the RECEIVER does when Emacs violates that. §11 defines no failure behavior; the module sections do not either. §18.1 gives dialog.show's error set as 1201/1401/1301; §20.2 (SPEC.md:2752) fixes 1001/1002/1003/-32602 for cap-name, permission, failure, and Args faults, and only says elsewhere (SPEC.md:2727) that "`capability.invoke` remains unavailable unless `capabilities` was granted" without naming a code; §21.1 gives 1101. Two mutually incompatible readings survive:

(A) -32601 method-not-found — the method simply does not exist in this session. But §7.3 (SPEC.md:506) and §12 rule 4 (SPEC.md:976) both scope -32601 to UNKNOWN methods, and a registered EBP 2 method is known.
(B) 1001 cap-unsupported — §8 (SPEC.md:558) glosses 1001 as "Capability was not advertised or is unavailable", which is a verbatim description of this case.

A third reading, 1204 session-state, is also reachable since §10.1 calls READY's legal traffic "All negotiated methods". The impl picked (A) at every gate: CompanionEngine.kt:870 (reminders.set), :1004 (triggers.set), :1064 (capability.invoke), :1209 (edit.apply), :1253 (edit.resync), :1403 (dialog.show) all `respondError(id, -32601, "Method not found", "method-not-found")`. Nothing pins that choice, and MethodSpec (MethodRegistry.kt:8-12) carries no capability field at all, so the decision lives as six scattered string literals.

The SPEC also leaves the gate's ORDERING undefined relative to §7.3's "sender, class, allowed session state, and parameters" list, which omits capability. The impl is internally inconsistent as a result: handleRemindersSet/handleTriggersSet/handleCapabilityInvoke/handleEditApply/handleEditResync check the grant BEFORE params, while handleDialogShow validates params first (CompanionEngine.kt:1398-1400) and only then checks `surfaces.dialog` (:1403).

**Failure scenario:** Emacs negotiates `wants: ["theme"]` and, through a bug or a stale cache, sends `dialog.show`. Companion A (this impl) answers -32601. Companion B, reading §8's 1001 gloss, answers `1001 cap-unsupported` with `data.kind: "cap-unsupported"`. Emacs's error handling diverges on the same wire input: -32601 reads as "peer is an older/other implementation that lacks this method" and plausibly triggers a capability-probing or downgrade path, while 1001 reads as "this session did not negotiate it" and triggers a renegotiate-on-reconnect path. Neither Companion can be called nonconforming, and no golden or contract row discriminates them. Secondarily, dialog.show with `surfaces.dialog` ungranted AND malformed params returns -32602 from this impl while every other ungranted method returns -32601 for the same class of caller error.

**Proposed fix:** Amend §11 with a sentence directly under the table: "A request whose §11 capability is absent from `granted` MUST receive `1001 cap-unsupported`; a notification whose capability is absent MUST be logged and dropped. The capability gate is evaluated after the sender, class, and session-state checks of Section 7.3 and before parameter validation, so an ungranted method is refused identically whatever its params contain. `-32601` remains reserved for methods absent from this registry." Add a `capability: String?` field to contract.json-backed MethodSpec so the gate is table-driven, then replace the six literal -32601 sites with one central check in handleRequest/handleNotification (which also fixes handleDialogShow's ordering).

## [P2] [unverified] §13.1 — §11/§13.1 leave `surface.remove` of an UNREPORTED surface in an ungranted namespace undefined; the impl mints a permanent tombstone, letting a zero-capability session exhaust max_surface_ids until pairing revocation

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SurfaceStore.kt`:202  
**SPEC line:** 1004  
**Auditor:** Audit SS11 (method registry) and SS12 (versioning and compatibility). 

**SPEC quote:**
> `surface.update` MUST reject a namespace whose
required capability/profile was not granted; `surface.remove` remains legal for
any surface reported in the welcome so stale persistent state can be retired.

**Detail:** §11's row for surface.remove (SPEC.md:928) reads `| surface.remove | Emacs | request | S, R | core for reported surfaces | 13 |` — the capability is core only FOR REPORTED SURFACES. §13.1 (SPEC.md:1004-1006) and §10.4 (SPEC.md:911-913, "Emacs MAY always send a revisioned `surface.remove` for a surface reported in the welcome, even when it did not request that surface's presentation capability") both carefully scope removal's exemption to welcome-reported surfaces. Neither says what a Companion does with `surface.remove` for a surface ID it has NEVER seen, in a namespace whose capability was not granted. §13.3 describes only the revision comparison. Two readings:

(A) surface.remove has no capability gate whatsoever; a never-seen ID simply gets a tombstone at the given revision (the impl's reading: `handleSurfaceRemove`, CompanionEngine.kt:664-690, validates only the ID grammar and comments "SPEC 13.1: removal is legal for any reported surface, no cap gate" while enforcing no reported-ness at all; `SurfaceStore.remove`, SurfaceStore.kt:202-219, takes `record ?: Record(-1,false,null,null,emptyMap())` and inserts it).
(B) The reported-surface exemption is exactly that — an exemption — so removing an UNREPORTED surface still requires the namespace capability, mirroring surface.update.

Reading (A) collides with §13.1's own durability rule (SPEC.md:1015-1017): "A Companion MUST retain each tombstone revision floor until pairing revocation and MUST NOT reclaim it merely to admit a reused or new ID." Under (A) the tombstone table is a write-only, capability-free, permanently-retained resource. Nothing in §23.5 or §4.5 closes this, because `max_surface_ids` is a limit, not a permission.

**Failure scenario:** Emacs authenticates with `wants: []`, so `granted` is empty and no surface capability exists in the session. It then issues 4096 requests `surface.remove {surface:"widget:junk-0000", revision:0}` … `{surface:"widget:junk-4095", revision:0}`. Each passes CompanionEngine.kt:664-690 (grammar-valid ID, no cap gate, no reported-ness check) and SurfaceStore.kt:202-219 creates a fresh `Record` tombstone, up to `maxSurfaceIds` = 4096 (the reference limit at SPEC.md:794). Every one of those tombstones MUST be retained until pairing revocation. From the next connection on, every legitimate `surface.update` and `surface.remove` for a NEW `app:*` ID hits `records.size >= maxSurfaceIds` and receives `1201 content-invalid` with `data.reason:"surface-limit"` (SurfaceStore.kt:207-208), permanently, with no protocol-level recovery short of revoking the pairing. Under reading (B) the same 4096 requests would all have been refused because `surfaces.widget` was never granted.

**Proposed fix:** Amend §13.1 to close the case explicitly, e.g.: "`surface.remove` is core only for a Surface ID the authenticated welcome reported. For a Surface ID the Companion has never seen, `surface.remove` is gated on the same namespace capability as `surface.update`; an ungranted namespace MUST receive `1001 cap-unsupported` and MUST NOT create a tombstone. A Companion MUST NOT allocate a `max_surface_ids` slot for an unreported ID whose namespace capability the session did not negotiate." Then, in `handleSurfaceRemove` (CompanionEngine.kt:664-690), resolve the namespace capability as `handleSurfaceUpdate` does at CompanionEngine.kt:571-579 and apply it whenever `surfaces.revisionOf(surface) == null` (i.e. the ID is not already known).

## [P2] [unverified] §13.1 / §7.3 — No error code is defined for invoking a capability-gated method or emitting capability-gated content without the grant

**SPEC line:** 1004  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 1 thr

**SPEC quote:**
> `surface.update` MUST reject a namespace whose
required capability/profile was not granted; `surface.remove` remains legal for
any surface reported in the welcome so stale persistent state can be retired.

**Detail:** §13.1 says "MUST reject" and names no code. §7.3's dispatch checklist (line 503) — "A receiver MUST verify the method's sender, class, allowed session state, and parameters before invoking a handler" — omits the capability gate entirely, and its five enumerated outcomes cover unknown method, wrong sender, wrong class, and bad params, but not "known method, correct sender/class/state, capability not granted." §10.2 line 840 states the sender obligation ("Emacs MUST NOT invoke a capability-gated method or emit capability-gated content unless the capability was granted") with no receiver response defined. §8 defines exactly the needed code — `1001` `cap-unsupported` "Capability was not advertised or is unavailable" — but no section in §1-13 requires it; the only place the SPEC mandates 1001 is §20.2 line 2752, for an unsupported `capability.invoke` name. Four readings are all defensible: -32601 method-not-found (the method is not available this session), 1001 cap-unsupported (§8's stated meaning), 1204 session-state, or 1201 content-invalid. The reference implementation uses THREE of them: -32601 for `dialog.show`/`reminders.set`/`triggers.set`/`capability.invoke`/`edit.apply` without the grant (CompanionEngine.kt:1403, 870, 1004, 1064, 1209) and 1201 with data.reason "namespace-not-granted" for an ungranted surface namespace (CompanionEngine.kt:577).

**Failure scenario:** Emacs did not request `surfaces.dialog` (or the Companion did not grant it) and, through an application bug or version skew, sends `dialog.show`. Companion A answers -32601, from which Emacs concludes the peer does not implement dialogs at all and permanently disables the feature for that Companion build. Companion B answers 1001 with data.kind "cap-unsupported", from which Emacs concludes the capability merely was not negotiated and re-requests it on the next reconnect. The same wire input yields opposite long-lived client behavior, and §12 rule 4 ("Unknown request methods receive `-32601`") makes reading A actively misleading, since the method is known and merely ungranted.

**Proposed fix:** Amend §7.3 to add the capability gate to the verification list and one bullet: "A request whose method is capability-gated and whose capability was not granted MUST receive `1001 cap-unsupported`; the method is known, so `-32601` MUST NOT be used. A notification in the same position MUST be logged and dropped." Amend §13.1 to name the code for content-level gates: "`surface.update` MUST reject a namespace whose required capability/profile was not granted with `1201 content-invalid` and `data.reason: \"namespace-not-granted\"`" (content-level, because the method itself is core). Add both to §24.1's required behaviors.

## [P2] [unverified] §13.2 — §13.2's and §14.6's mandatory `state.changed` flushes are unsatisfiable in SYNCING, where `state.changed` is illegal

**SPEC line:** 1068  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 1 thr

**SPEC quote:**
> An applied result additionally acts as a `state.changed` barrier for the
target surface: Section 14.6's reconciliation rules require the Companion to
flush or discard pending input-state notifications before returning it.

**Detail:** §11's registry gives `state.changed` the state column `R` (line 931) while `surface.update`, `surface.remove`, `queue.replay`, and `event.action` are all legal in `S, R` (lines 927-930), and §10.3 requires Emacs to push surface updates and run replay precisely while in SYNCING. Two normative flush duties therefore land in a state where the flush frame itself is illegal: (1) §13.2's barrier above, restated in §14.6 as "Before returning the result of a `surface.update` or `surface.remove` that changes a surface's revision floor, the Companion MUST flush that surface's pending debounced `state.changed` notifications"; and (2) §14.6's state-before-action rule, "If the Companion debounces state publication, it MUST flush every divergent stateful value as ordered `state.changed` notifications before sending an `event.action` whose handler could observe those values" — which is impossible for the durable events `queue.replay` sends during SYNCING. §10.1 line 751-753 makes the consequence concrete: a `state.changed` sent in SYNCING "MUST be logged and dropped" by Emacs. Nothing in §13.2, §14.6, or §10.3 states which of "flush", "discard", or "defer to READY entry" governs in SYNCING; §10.3's READY-entry flush exists but is never named as the resolution of §13.2's barrier, and §13.2's word "discard" is left as a permitted alternative.

**Failure scenario:** A user edits `title` on `app:main` while offline; the value is retained per §14.6 line 1511. On reconnect, Emacs pushes surface.update revision 42 during SYNCING. Companion A reads §13.2 literally and DISCARDS the pending notification before returning `applied` (the word the SPEC offers) — the user's offline text is never reported to Emacs and is overwritten by the next authored snapshot. Companion B sends `state.changed` in SYNCING to honor the barrier; Emacs drops it under §10.1 and the Companion clears its pending flag — same silent data loss. Companion C (the reference) defers to the §10.3 READY-entry flush, preserving the value but breaking the barrier promise "once Emacs has observed it, no `state.changed` for that surface with an older `revision_seen` can arrive."

**Proposed fix:** Amend §13.2 and §14.6 with an explicit SYNCING scope: "While the session is in `SYNCING`, `state.changed` MUST NOT be emitted. A pending divergent value MUST be retained — never discarded — and is flushed on entry to `READY` under Section 10.3; the update-result barrier of this paragraph applies only in `READY`, and in `SYNCING` the equivalent guarantee is that every value pending at the time of an applied result is flushed at `READY` entry ahead of any released event, carrying its originating `revision_seen`." Add to §14.6's state-before-action paragraph: "A durable event replayed during `SYNCING` carries its own occurrence-time `capture_fields` and is exempt from this flush rule, which applies only in `READY`."

## [P2] [unverified] §13.2 — §13.2's reset_input_ids validity rule contradicts §16.2's unadvertised-type degradation: whether a degraded stateful-typed node is 'a stateful node in the submitted spec' is unresolved

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:140  
**SPEC line:** 1040  
**Auditor:** Audit SS13.5 and SS13.6 (input state, drafts, draft reconciliation on 

**SPEC quote:**
> `reset_input_ids` values MUST be distinct and MUST name non-password stateful
nodes in the submitted `spec`; another value makes the request invalid.

**Detail:** §14.6 (line 1461) defines statefulness purely by type: "Stateful nodes are `text_input`, `checkbox`, `switch`, `enum_list`, and `slider`, plus an `editor` whose `publish_state` is `true`." §16.2 (lines 1707-1713) says a known type absent from the target's advertised node_types "MUST be treated EXACTLY as an unknown type: its subtree is scanned for nested valid nodes, but its per-type schema is not applied, it registers no stateful draft, and it dispatches nothing", and frames that as "defensive behavior for a nonconforming or version-skewed sender" whose whole point is that the receiver MUST NOT crash. The two readings of §13.2 diverge for a slider whose type the profile omits: under §14.6's type list it IS a stateful node in the submitted spec, so naming it in reset_input_ids is valid and the reset is simply a no-op; under §16.2's "registers no stateful draft" it is not, so the request "is invalid" and §16.1's "MUST reject the entire update with 1201 content-invalid" destroys the whole surface. The reference implementation silently picks the second reading: validateNode returns early for unadvertised types before stateful registration (SpecValidator.kt:402 and :563-569), and validateResetIds resolves against that profile-gated map (SpecValidator.kt:140-141, "not a stateful node in spec"). The identical ambiguity governs §14.1 capture_fields resolution, which uses the same map (SpecValidator.kt:121-125), so the same version skew also nukes a surface merely for capturing a degraded node's value.

**Failure scenario:** A Companion build advertises app.node_types without `slider`. A version-skewed Emacs pushes a settings surface: a column with 12 valid Core Node Set children, one {t:"slider", id:"vol", on_change:{...}}, and reset_input_ids:["vol"]. Reading A: the Companion accepts the update, degrades the slider to nothing per §16.2, and the user still sees the other 12 controls. Reading B (what the impl does): the entire surface.update is rejected with 1201 content-invalid at path reset_input_ids[0], and the user's settings screen never appears at all — the opposite of the graceful degradation §16.2 promises for exactly this sender. Both are defensible from the text.

**Proposed fix:** Amend §13.2 (and mirror it in §14.1 for capture_fields) to state explicitly whether a node whose type is in §14.6's stateful list but absent from the target profile's advertised node_types counts as "a stateful node in the submitted spec". Recommended wording: it does count for the purposes of reset_input_ids and capture_fields validity — the request stays valid, the reset is a no-op, and a captured degraded node contributes that node type's default value — so §16.2's degrade-don't-reject guarantee is not silently overridden by §13.2/§14.1. If the opposite is intended, say so in §16.2 so implementers know a degraded node makes a naming request content-invalid.

## [P2] [unverified] §13.4 (vs §13.1, §10.2, §22.1) — §13.4 defines no SurfaceSpec variant for the `tile:*` namespace registered by amendment #39

**SPEC line:** 1091  
**Auditor:** Audit SS13.1 through SS13.4 (surface namespaces, surface.update / surf

**SPEC quote:**
> The namespace determines the exact SurfaceSpec variant:

| Namespace | Schema |
|---|---|
| `app:*` | One root Node or the multi-view object below |
| `notification:*` | `{body: Node, meta?}` from Section 18.5; multi-view is prohibited |
| `widget:*` | `{title: string, body: Node, empty?: Node, header_action?: ActionDescriptor}`; multi-view is prohibited | (SPEC.md:1091-1097)

**Detail:** Amendment #39 registered `tile:<name>` in the §13.1 namespace table (SPEC.md:997), added `tile` to §10.2's applicable-target and profile-required clauses (SPEC.md:845, 854), and registered `surfaces.tile` in §22.1 (SPEC.md:3262) — its changelog entry asserts "§13's revision/tombstone/limit/update/remove rules apply unchanged". But §13.4, the section that says the namespace determines the exact SurfaceSpec variant, was not amended and has no `tile:*` row; contract.json likewise carries `surfaces.tile` in `capabilities` with no tile spec shape anywhere. An implementer granting surfaces.tile has no normative schema and must invent one. The permitted readings diverge observably: (a) tile falls through to the `app:*` row (root Node OR multi-view object), which would make a tile a navigable multi-view surface addressable by `view.switch`; (b) tile mirrors `widget:*` (`{title, body, empty?, header_action?}`), since a Quick-Settings tile is a chrome-wrapped slot much closer to a home widget than to a full screen; (c) tile has no defined variant, so every tile update MUST be 1201 content-invalid and the capability is unusable. Three further sub-questions are unresolved by construction: whether `views`/`initial_view` are prohibited for tile (the prohibition is written per-row for notification and widget only, while line 1100 independently restricts `current_view` to multi-view `app:*` — so under reading (a) a tile could legally carry `views` yet never receive `current_view`); whether tile surfaces may contain stateful nodes and therefore participate in §13.6 draft reconciliation and welcome `input_state`; and whether `stale_spec`/`stale_after_s` apply. The reference impl reads it as (c) by omission — SurfaceStore's SURFACE_ID regex is `(app|notification|widget):...` (SurfaceStore.kt:11), so every tile ID is rejected as 1201 `surface-id` before the capability gate is consulted.

**Failure scenario:** Two conforming Companions both advertise `surfaces.tile`. Emacs pushes surface.update {surface:"tile:pomodoro", revision:1, spec:{t:"text",text:"25:00"}}. Companion A (reading (a)) applies it; Companion B (reading (b)) returns 1201 content-invalid because the spec is not `{title, body, ...}`. The identical push is simultaneously conformant and non-conformant, and Emacs has no advertisement to distinguish them — surface_profiles.tile carries node_types/builtins/features, never the wrapper shape.

**Proposed fix:** Amend §13.4's table with a `tile:*` row that pins the wrapper explicitly, e.g. `| tile:* | {label: string, body: Node, state?: "active"|"inactive"|"unavailable", on_tap?: ActionDescriptor}; multi-view is prohibited |`, or, if a tile is intended to be a plain root Node, say `| tile:* | One root Node; multi-view is prohibited |`. In the same amendment state whether tile surfaces may carry stateful nodes (and thus §13.6 drafts and welcome input_state) and whether stale_after_s/stale_spec apply, and add the chosen shape to contract.json so validate.py can witness it.

## [P2] [unverified] §13.5 — §13.5 never states the time base for the stale_after_s clock, and it must both survive process death and start only at a READY disconnect

**SPEC line:** 1134  
**Auditor:** Audit SS13.5 and SS13.6 (input state, drafts, draft reconciliation on 

**SPEC quote:**
> If `stale_after_s` is absent, the snapshot never becomes stale solely because
of disconnection. If present, its clock starts when the preceding `READY`
session disconnects, MUST survive Companion process death, and ends only when a
new session reaches `READY`.

**Detail:** Every other duration in the SPEC pins its time base: §15.2 defines queue expiry against "the effective wall-clock time" with a durable per-pairing high-water mark and an explicit rollback rule; §21.5 reuses that same effective wall clock by reference; §14.6 gives the password submission a "hard 30-second monotonic deadline". §13.5 references none of them, yet imposes a requirement — survival across Companion process death — that a naive monotonic timer cannot satisfy. Three defensible implementations follow, each with different user-visible behavior: (a) persist the system wall-clock instant of the READY disconnect and compare against the current wall clock — a user clock rollback postpones staleness indefinitely and a forward jump makes every cached surface instantly stale, exactly the attack §15.2 bothers to close for the queue; (b) use §15.2's effective wall clock with the per-pairing high-water mark — rollback-proof and consistent with the rest of the document; (c) use a boot-relative elapsed-realtime counter (Android SystemClock.elapsedRealtime), which survives process death but resets at reboot, so a week-old cached surface renders as fresh after a phone restart. A second undefined case rides along: the clause anchors the clock to "the preceding READY session", so when a surface is accepted during SYNCING and the transport dies before READY there is no preceding READY session and it is unstated whether that snapshot can ever become stale. §24.1 makes "disconnected staleness semantics" a Companion MUST, so an implementer cannot skip past the ambiguity.

**Failure scenario:** Companion A implements reading (b), Companion B implements reading (c). Emacs pushes app:agenda with stale_after_s:3600 and stale_spec showing 'Agenda may be out of date'. Emacs disconnects; four hours later the user reboots the phone and opens the Companion while Emacs is still offline. Companion A shows the stale_spec (4h > 1h under the effective wall clock). Companion B shows the fresh cached agenda, because elapsedRealtime restarted at 0 at boot and only 30 seconds have elapsed. Both conform to §13.5 as written, and the user of B acts on hours-old data the author explicitly marked as expiring.

**Proposed fix:** Amend §13.5 to read: the clock uses the Section 15.2 effective wall clock; the Companion MUST durably record the effective-wall-clock instant at which the preceding READY session disconnected, and MUST NOT let a clock rollback extend a snapshot's freshness. Add a sentence resolving the no-preceding-READY case — recommended: a snapshot accepted in a session that never reached READY does not become stale until the first READY session that follows it disconnects.

**Verdicts:**
- `SPEC TEXT` refuted=False (high): The quote is verbatim and normative. SPEC.md:1134-1137 reads exactly "If `stale_after_s` is absent, the snapshot never becomes stale solely because of disconnection. If present, its clock starts when the preceding `READY` session disconnects, MUST survive Companion process death, and ends only when a new session reaches `READY`." — a MUST inside §13.5 (a normative subsection, not a note or example

## [P2] [contested] §14.3 — §14.3 leaves the index basis for on_add_row/on_add_col undefined when the table contains `rule` rows

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/LayoutNodes.kt`:509  
**SPEC line:** 1340  
**Auditor:** Audit SS14.1 through SS14.3 (ActionDescriptor shape, the dotted action

**SPEC quote:**
> For
`on_add_row` and `on_add_col`, `index` is the requested insertion slot in the
current axis: it is before the existing item at that index, and an index equal
to the current count appends.

**Detail:** §17.3 defines a `table` as `rows: TableRow[]` where a TableRow is one of `{kind:"data"}`, `{kind:"header"}`, or `{kind:"rule"}` (SPEC.md:1896-1906). A `rule` occupies a slot in the `rows` array but is not a content row. §14.3 says `index` is "the requested insertion slot in the current axis" and that "an index equal to the current count appends", but never says what "the current count" counts, so two readings are equally supported: (A) the length of the authored `rows` array, in which case rules occupy indices and an append is `rows.length`; (B) the number of content (data + header) rows, in which case rules are invisible to the index. Emacs, which owns the authored array, will naturally read (A); the reference takes (B): LayoutNodes.RenderTable computes `nrows = specs.count { it is CellsSpec }` (LayoutNodes.kt:495) — `specs` is built at 470-488 and models rules as a separate `RuleSpec` — and injects that as `index` at LayoutNodes.kt:509. The same ambiguity exists for `on_add_col`, where the reference uses `maxOf { it.cells.size }` (LayoutNodes.kt:496) although rows may be ragged, so "the current count" of columns is itself not defined for a ragged table.

**Failure scenario:** A table has `rows:[{kind:"header",...},{kind:"rule"},{kind:"data",...},{kind:"data",...}]` (rows.length 4, content rows 3). The user taps the "Add row" affordance at the bottom, meaning append. The Companion injects `index: 3`. Emacs, reading the index against its own `rows` array, inserts before `rows[3]` — i.e. between the two data rows — so the new row appears in the middle of the table instead of at the end. A conforming Companion using reading (A) would have sent 4. Nothing in the SPEC lets either side know which is meant.

**Proposed fix:** Amend §14.3's `on_add_row`/`on_add_col` paragraph to pin the basis explicitly. Recommended text: "For a `table`, the `on_add_row` index is an index into the authored `rows` array and counts every `TableRow`, including `rule` rows; the current count is therefore `rows.length`. The `on_add_col` index is an index into a row's `cells` array; for a ragged table the current count is the maximum `cells` length over all `data` and `header` rows." Add a matching sentence to §17.3's table paragraph cross-referencing §14.3, and add a `widgets.golden` vector exercising a table with a `rule` row so the basis is pinned by fixture as well as prose.

**Verdicts:**
- `SPEC TEXT` refuted=True (high): The quoted §14.3 sentence is verbatim and normative (SPEC.md:1339-1342), but the claimed ambiguity is resolved by §17.3: the table's axis is declared `rows: TableRow[]` (SPEC.md:1871) and "A `TableRow` is one of" data / header / `{"kind":"rule"}` (SPEC.md:1908-1916). A rule therefore IS an "existing item at that index", so "the current count" is `rows.length`. Reading (B) requires a "content row" 
- `CODE TRUTH` refuted=False (high): Code behaves exactly as claimed and nothing handles it elsewhere. LayoutNodes.kt:495 `val nrows = specs.count { it is CellsSpec }` counts only header/data rows (rules are a separate `RuleSpec`, built at 470-488) and 509 injects that as `index`; 496 uses `maxOf { it.cells.size }` for `ncols` over possibly-ragged rows. SpecValidator.kt:57-58 and contract.json:426-427 only assert the member NAME `ind
- `MATERIALITY` refuted=False (high): SPEC.md:1340-1341 is the only place in SPEC.md, contract.json, SPEC-CHANGES.md or docs/ that mentions "insertion slot"/"current axis", and it never says what "the current count" counts; §17.3 (SPEC.md:1906) makes `{"kind":"rule"}` a member of the `TableRow` union, so it occupies a slot in `rows`. The reference resolves this silently to the content-row basis at LayoutNodes.kt:495 (`val nrows = spec

## [P2] [unverified] §14.3 / §17.3 — §14.3's `on_add_row`/`on_add_col` index is undefined for tables containing `rule` rows or ragged cell counts

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/LayoutNodes.kt`:495  
**SPEC line:** 1340  
**Auditor:** Audit SS17.4 through SS17.6 (layout nodes, the scaffold and its slots,

**SPEC quote:**
> For `on_add_row` and `on_add_col`, `index` is the requested insertion slot in the current axis: it is before the existing item at that index, and an index equal to the current count appends.

**Detail:** "the current count" in "the current axis" is never resolved for the two ways a §17.3 table departs from a rectangular grid. (1) ROWS: `rows` is a `TableRow[]` whose members may be `{"kind":"rule"}`, which occupies an array slot but carries no cells. Reading A counts every TableRow (append index = `rows.length()`); reading B counts only data-bearing rows (`header`+`data`). The reference impl takes B — `val nrows = specs.count { it is CellsSpec }` (LayoutNodes.kt:495), dispatched as `index` at 509 — while an Emacs handler that splices into the authored `rows` array naturally implements A. (2) COLUMNS: the SPEC nowhere defines a table's column count, and §17.3 does not require rows to have equal cell counts. The impl uses the maximum across rows (`maxOf { it.cells.size }`, LayoutNodes.kt:496); the first row's count, the header row's count, or `aligns.length()` are equally available readings. The `aligns` array is likewise positional with no stated column basis.

**Failure scenario:** Emacs pushes `rows: [{kind:"header",cells:[…]}, {kind:"rule"}, {kind:"data",cells:[…]}, {kind:"data",cells:[…]}]` with `on_add_row`. The user taps "+": the Companion sends `args.index = 3`. Under the SPEC's positional rule that means "before the existing item at index 3", i.e. before the LAST data row — so the new row is inserted second-to-last instead of appended, and every subsequent append lands one slot earlier. Under reading A the Companion would have sent 4 and appended correctly.

**Proposed fix:** Amend §14.3 (or the §17.3 table prose) to pin both axes, e.g.: "For `on_add_row`, the axis is the authored `rows` array and its count includes `rule` rows, so an index equal to `rows.length()` appends. For `on_add_col`, the current column count is the greatest `cells` length among the snapshot's `data` and `header` rows; `aligns` indexes that same column axis." Then correct LayoutNodes.kt:495 to count `rowsJson.length()`.

## [P2] [unverified] §15.1 / §21.2 (with §21.5) — §15.1's `1601 queue-full` admission rejection and §21.2's durable-transaction rule give no precedence for a trigger occurrence, stranding `on_fire` and one-shot completion markers

**SPEC line:** 1566  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 14 th

**SPEC quote:**
> If storage fails, the Companion MUST NOT claim that the interaction was queued.
It MUST notify the user of the failure. If queue capacity is exhausted, it MUST
reject admission with a visible diagnostic equivalent to `1601 queue-full`.

**Detail:** §21.2:2967-2977 makes one trigger occurrence a five-step pipeline whose step 3 is a single durable transaction committing "the new throttle state, any one-shot completion or boot-generation receipt, and, for `queue` or `wake`, the complete event record and `queue_seq` in one transaction". §21.2:2985-2987 then says "If the durable transaction fails, the Companion MUST NOT execute local responses or claim remote admission." §15.1:1566-1568 separately says queue capacity exhaustion "MUST reject admission with a visible diagnostic equivalent to `1601 queue-full`". Nothing states whether queue-full is a "durable transaction failure" under §21.2 or a distinct admission-rejection outcome, and nothing states what happens to the NON-event contents of that transaction when the event record cannot be inserted. Two readings follow. Reading A (queue-full is a transaction failure): `on_fire` is not executed, throttle is not consumed, the one-shot completed marker required by §21.5:3138-3140 ("the Companion MUST commit a completed marker in Section 21.2's transaction even for `drop`") is never written, and the boot-generation receipt is never written — so the occurrence re-evaluates as eligible on the next sample and retries indefinitely. Reading B (queue-full rejects only the remote portion): the Companion commits throttle/one-shot/boot state, runs `on_fire`, and drops the remote event with a diagnostic. The SPEC also never says who sees the "visible diagnostic" when the occurrence is unattended at 03:00 with no session.

**Failure scenario:** `max_queued_events` is saturated because Emacs has been offline for a week. A registered `{"type":"time","params":{"at_ms":…},"policy":"queue","ttl_s":86400,"on_fire":[{"cap":"vibrate","args":{"ms":300}}]}` becomes eligible. Companion A (reading A) fails the transaction: the phone never vibrates, the completed marker is never committed, and because §21.5 says the one-shot has not been admitted, the scheduler re-evaluates it on every tick — an unbounded fire/fail loop that drains the battery and, per §15.1, raises a user-visible `queue-full` diagnostic on each iteration. Companion B (reading B) vibrates once, marks the one-shot completed, and drops the remote event silently. Same registration, same device state: one implementation loops forever, the other completes cleanly.

**Proposed fix:** Amend §21.2 to give queue-full its own disposition, distinct from storage failure. Add after §21.2:2987: "Exhausted durable queue capacity (§15.1) is an admission rejection of the REMOTE portion only, not a durable-transaction failure. The Companion MUST still commit the occurrence's throttle state, one-shot completion marker, and boot-generation receipt in step 3, MUST still execute `on_fire` in step 4, and MUST NOT create the remote event record; it MUST record a `1601 queue-full` diagnostic. A durable-transaction failure means the storage layer could not commit the transaction it attempted, and only then are steps 4 and 5 suppressed." Also state that for an unattended occurrence the §15.1 "visible diagnostic" obligation is satisfied by a rate-limited Companion-local record surfaced through `companion.settings.open`, not by a per-occurrence user-facing alert.

## [P2] [unverified] §15.3 — §15.3 defines no stable stop for a pump that cannot progress for a non-error reason, so an outstanding queue.replay may never be answered

**SPEC line:** 1601  
**Auditor:** Audit SS15 (durable queue and replay) against DurableQueue.kt, QueueSt

**SPEC quote:**
> `queue.replay` resumes the pump and asks it to run to a stable stop. If a
durable event request was already in flight when replay arrived, the replay
MUST join that operation rather than send a duplicate concurrently, and its
summary MUST include the joined disposition.

**Detail:** §15.3 enumerates exactly four things that stop the pump: expiry (counted), a permanent result (delete and advance), a well-formed JSON-RPC error (retain and pause), and an invalid result shape (retain, one `log.error`, close). It never states an obligation to *answer* the outstanding `queue.replay` request, nor a bound on how long the Companion may hold it, nor what happens when the pump is blocked for a reason that is neither an error nor exhaustion. Two such states exist in a conforming Companion and the SPEC resolves neither:

(a) A §21.2 head whose local `on_fire` has not yet completed. §21.2 requires the local half to run before the remote event is eligible, but §15.3's stable-stop list has no entry for it. Reading 1: this is a stable stop — conclude with `remaining > 0`, `blocked_by: null`. Reading 2: it is not a stop — keep the request open until the local step finishes. The reference takes reading 2 (`Delivery.PendingLocal -> return` without `concludeReplay`, CompanionEngine.kt:501; `DurableQueue.beginDelivery`, DurableQueue.kt:85). If the local step then fails and the record is rolled back (`TriggerFiringService.kt:176-178` deletes the record and returns without ever invoking `onDurableAdmitted`), nothing re-drives the pump and the request is simply never answered.

(b) The "already in flight" request belongs to a connection that §5.2 has superseded but whose teardown has not yet released the in-flight mark. The reference tests `queue.hasInFlight()` globally (CompanionEngine.kt:470) and skips `pumpAdvance`; when the old connection's `close()` later calls `queue.clearInFlight`, nothing re-drives the new connection's pump.

Either way the §10.3 barrier stalls: Emacs is required to "call `queue.replay` and wait for it to conclude" before `session.ready`, and the SPEC gives it no permitted timeout either — ebp.el has to invent one (a 300 s jsonrpc timeout at ebp.el:706 that then closes the connection with `replay-failed`, ebp.el:693).

**Failure scenario:** A `policy:"queue"` trigger with a non-empty `on_fire` fires; `TriggerFiringService.admit` commits the queue record with `pending_local: true` and enters `commit()`. Emacs's §10.3 barrier `queue.replay` arrives on the reader thread in that window: `handleQueueReplay` sees no in-flight record, calls `pumpAdvance`, `beginDelivery` returns `PendingLocal`, and the handler returns with `replayId` still set and no response emitted. `commit()` then throws (trigger-store `renameTo` failure), so `admit` deletes the record and returns at TriggerFiringService.kt:177-178 without queueing `onDurableAdmitted`. No further code path calls `pumpAdvance`, so the `queue.replay` request is never answered; Emacs blocks the barrier for 300 s and then tears the connection down. Both endpoints are conforming to the letter of §15.3.

**Proposed fix:** Amend §15.3 to (1) enumerate "the head is withheld for a Companion-local reason (for example a Section 21.2 local response that has not completed)" as a stable stop that concludes the replay with `remaining` counting the withheld records and a new `blocked_by` value `"pending-local"`; (2) state that a Companion MUST answer an outstanding `queue.replay` — with a summary or an error — before it emits any other frame that is legal only after the barrier, and MUST answer it (or close) within a bounded time; and (3) state that an in-flight durable request MUST be considered released when its originating connection closes, so a new session's replay never joins a dead operation. Correspondingly amend §10.3 to permit Emacs a bounded wait on step 4 and define the failure disposition (close vs. proceed) explicitly.

## [P2] [unverified] §16.5 (with §16.1, §12) — SPEC leaves undefined what a Companion does with an out-of-range or wrong-typed OPTIONAL universal attribute — §16.1's rejection list names only required fields, and §16.5's `align_self` enum has neither a safe fallback nor a rejection rule (contradicting §12 rule 6)

**SPEC line:** None  
**Auditor:** Audit SS16 (UI document model) — SS16.1 node identity and the identity

**SPEC quote:**
> The following members MAY appear on any node unless its meaning is nonsensical
for that node. Numeric layout values are finite, non-negative logical
density-independent units (`dp`) unless stated otherwise.  ...  A malformed node, invalid required field, invalid action descriptor,
duplicate stateful-node ID, or resource-limit violation MUST reject the entire
update with `1201 content-invalid`.  ...  6. Unknown enum values MUST NOT be guessed. The applicable schema MUST either
   define a safe fallback or require rejection of the containing object.

**Detail:** §16.5 states the constraints (finite, non-negative dp; `fill_fraction` 0..1; `aspect_ratio` > 0; `weight` > 0; `alpha` 0..1; `align_self` one of four literals) but never states the receiver's duty when they are violated. §16.1's rejection trigger list mentions "invalid required field" — every §16.5 member is optional — and "malformed node", which is nowhere defined. §16.3 covers only *unknown* fields, not known-but-invalid ones. Two readings are equally supportable: (a) an invalid optional universal attribute makes the node malformed and MUST 1201 the whole update; (b) it is ignored and the documented default applies. The reference implementation takes (b) for §16.5 — SpecValidator has no universal-attribute rules at all (grep for alpha/fill_fraction/weight/corner/bg/clip/align_self in SpecValidator.kt returns nothing), and Attributes.kt's `safeDp`/`safeFraction`/`safeAspect`/`safeAlpha` (Attributes.kt:39-49) return null so the modifier is skipped — while taking (a) for the structurally identical §17.x optional numerics: `text.max_lines` ≤ 0, `progress.value` outside 0..1, `date_stamp.day` outside 1..31 and `chart.height` ≤ 0 all throw ContentInvalid (SpecValidator.kt:501, 508-514, 515-522, 699-703). Separately, `align_self` is an enum whose Default column is "—"; §16.5 defines no safe fallback for an unrecognized value and requires no rejection, which is exactly what §12 rule 6 forbids a schema from doing.

**Failure scenario:** Emacs sends `{"t":"box","alpha":7,"fill_fraction":-1,"align_self":"middle","children":[{"t":"text","text":"hi"}]}` to two conforming Companions. Companion A (reading (a)) answers `surface.update` with `1201 content-invalid` and the surface never appears; Companion B (this implementation, reading (b)) accepts revision N, renders the box at alpha 1 with no fill and no alignment override, and reports the revision as accepted. Emacs cannot know which behavior to code against: under (a) it must never emit the node, under (b) it may rely on the defaults. The same divergence applies to `weight: -3`, `aspect_ratio: 0`, `corner: {"top_start": -4}` and `pad: {"start": "8"}`.

**Proposed fix:** Amend §16.5 with an explicit receiver rule, e.g.: "A universal attribute whose value violates its declared type or range is invalid. A Companion MUST ignore that single member and apply the member's stated default; it MUST NOT reject the update on that ground alone, and MUST NOT infer a value from the invalid one." Add the corresponding enum clause required by §12 rule 6: "An `align_self` value outside `start|center|end|stretch` MUST be ignored (no override applied)." Then state in §16.1 that "malformed node" means a non-object node, a missing `t`, a non-string `t`, or a violation of a REQUIRED member's type — so the rejection boundary is closed. Mirror the amended rule into `contract.json` (a `severity`/`on_invalid` marker per universal attribute) and align §17.x optional numerics with whichever rule is chosen, so the two families stop diverging.

## [P2] [unverified] §17 — §17 never states the disposition of a wrong-typed KNOWN optional member — reject, ignore, or coerce

**SPEC line:** 1774  
**Auditor:** Audit SS17.1 through SS17.3 (the node-type vocabulary preamble, conten

**SPEC quote:**
> The tables in this section are normative schemas. Every listed required member MUST be present and have the listed type. Every listed optional member MAY be omitted and then has the stated default or behavior.

**Detail:** The preamble binds a type only to *required* members; for an optional member it defines only the omitted case. §16.3 resolves the *unknown* optional field ("A Companion MUST ignore an unknown optional node field") but says nothing about a known member carrying the wrong JSON type. §16.1's rejection list names "a malformed node, invalid required field" — reading a wrong-typed optional member into "malformed node" is possible but not stated. §17.1's "a receiver MUST NOT apply type coercion omitted by them" forbids the third option without choosing between the first two. The reference does both, inconsistently, in the same function: `{"t":"text_input","id":"a","value":42}` rejects (SpecValidator.kt:410-411), `{"t":"progress","value":"half"}` rejects (line 510-511), but `{"t":"text","text":"x","selectable":"yes"}` is accepted and silently coerced by `optBoolean` (ContentNodes.kt:163), `{"t":"image","url":"https://…","content_scale":7}` is accepted, and `{"t":"slider","id":"s","on_change":{…},"values":"1,2,3"}` is accepted as a *continuous* slider because `optJSONArray` returns null (SpecValidator.kt:422 and InputNodes.kt:354 both take the null branch).

**Failure scenario:** Emacs emits `{"t":"slider","id":"vol","on_change":{"action":"v.set"},"values":"1,2,3","value":2}`. Reading (a) reject: `1201 content-invalid`, Emacs fixes the bug immediately. Reading (b) ignore-the-bad-member: the node becomes a continuous 0..1 slider and `value:2` is then out of range, so it *also* rejects — but with a different, confusing path. Reading (c), the reference: accepted as a continuous slider whose validator computed min=0/max=1 while `RenderSlider` reads `node.optDouble("min",0.0)`/`optDouble("max",1.0)` — and because org.json's `optDouble` coerces numeric *strings*, `{"min":"5","max":"10"}` makes the validator see 0..1 and the renderer see 5..10, so the two halves of the same Companion disagree about the node's domain.

**Proposed fix:** Add one sentence to the §17 preamble: "A listed optional member that is present MUST have the listed type; a present member of the wrong type makes the containing node malformed and MUST reject the entire update with `1201 content-invalid` under Section 16.1 — a receiver MUST NOT ignore it, substitute the default, or coerce it." (Or, if leniency is intended, state explicitly that it MUST be treated as omitted.) Either choice must then be projected through `contract.json.field_types` so validators agree.

## [P2] [unverified] §17.1 — §17.1/§17.2/§17.4 closed vocabularies have no §12 rule-6 disposition for an unrecognized value

**SPEC line:** 978  
**Auditor:** Audit SS17.1 through SS17.3 (the node-type vocabulary preamble, conten

**SPEC quote:**
> Unknown enum values MUST NOT be guessed. The applicable schema MUST either define a safe fallback or require rejection of the containing object.

**Detail:** §12 rule 6 makes a per-member disposition mandatory, and §17.2 supplies one for `text.style` ("unknown values fall back to `body`") — amendment #41 did the same for `dialog.style`. But five closed vocabularies in the assigned sections have neither a fallback nor a rejection rule: `font_weight` (§17.1 line 1799: "`normal`, `bold`, or an integer multiple of 100 from 100 through 900"), `image.content_scale` (§17.2 line 1813: "`fit` (default), `crop`, or `fill`"), `progress.variant` (§17.2 line 1817), `button.variant` (§17.4 line 1937) and `text_input.keyboard` (§17.4 line 1985). An implementer must invent one. The reference invents *guessing*, which rule 6 forbids by name: `fontWeightOf` (ContentNodes.kt:124-131) accepts any integer in 1..1000 — not just multiples of 100 — and additionally honours `"medium"` and `"light"`, two names the SPEC's vocabulary does not contain; `RenderImage` maps any unknown `content_scale` to `Fit` (ContentNodes.kt:74-78); `RenderProgress` treats anything but `"linear"` as circular (ContentNodes.kt:326); `RenderButton` treats anything but tonal/outlined/text as filled (InputNodes.kt:86-90); `keyboardTypeOf` maps anything unknown to `Text` (Renderer.kt:296-303). SpecValidator checks none of the five.

**Failure scenario:** Emacs authors `{"t":"text","text":"Heading","font_weight":"medium"}`. Under reading (a) — silent fallback, like `text.style` — the text renders at normal weight. Under reading (b) — reject, as §12 rule 6's second option and §16.1's "malformed node" permit — the whole `surface.update` fails with `1201`. Under reading (c), the reference's actual behaviour, the text renders at FontWeight.Medium, honouring a value outside the specified vocabulary. Three conformant-looking Companions produce three different outcomes for the same frame, and Emacs has no way to tell which it is talking to. `font_weight: 250` is the same split: round to 200, reject, or honour 250.

**Proposed fix:** Amend §17.1 with one sentence covering all of them, in the shape of amendment #41: "An unrecognized value of a closed-vocabulary member in this section (`font_weight`, `style`, `content_scale`, `variant`, `keyboard`, `align`, `arrange`, `alignment`, `shape`) MUST fall back to that member's stated default and MUST NOT cause rejection of the containing node; a Companion MUST NOT honour a value outside the listed vocabulary." Then add the corresponding negative cases to `validate.py`/the goldens, and tighten `fontWeightOf` to reject non-multiples of 100 and the unlisted names.

## [P2] [unverified] §17.3 — Layout `fill` is declared a boolean but its effect is never defined, so row/column geometry diverges between conforming Companions

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/LayoutNodes.kt`:122  
**SPEC line:** 1879  
**Auditor:** Audit SS17.4 through SS17.6 (layout nodes, the scaffold and its slots,

**SPEC quote:**
> | `row` | `children: Node[]` | `spacing`, `align`, `arrange`, `scroll`, `fill`. … | `column` | `children: Node[]` | `spacing`, `align`, `arrange`, `scroll`, `fill`. … `scroll` and layout `fill` are booleans.

**Detail:** `fill` appears only twice in §17.3 — once in each of the row and column rows — plus the type-only sentence at line 1879. No sentence anywhere in the SPEC says WHICH axis it fills or of what: §16.5 defines `fill_fraction` as "Fraction of available parent width" and `weight` as "Share of remaining main-axis space", but `fill` is tied to neither. At least three readings are permitted: (a) fill the container's MAIN axis (width for row, height for column); (b) fill the CROSS axis; (c) fill both (`fillMaxSize`). The reference implementation silently mixes (a) and (b): RenderRow maps `fill` to `fillMaxWidth()` (main axis, LayoutNodes.kt:122-126) and RenderColumn maps it to `fillMaxWidth()` too (cross axis, LayoutNodes.kt:146) — so the same member means opposite things on the two node types, and neither choice is derivable from the text. The overloading of the identifier makes it worse: `image.content_scale` has a `fill` VALUE (§17.2) and `CanvasOp.fill` is a Color (§17.5), both of which the SPEC does define, which is what makes the silence on layout `fill` read as an oversight rather than an intentional platform latitude.

**Failure scenario:** Emacs authors `{"t":"column","fill":true,"align":"center","children":[{"t":"text","text":"Signed out"}]}` intending a full-height centred empty state. Companion A (this one) fills only the width, so the text sits at the top of an otherwise unfilled parent; Companion B reads `fill` as main-axis and fills the height, centring vertically. The same document produces two materially different screens and the author has no way to express the intent portably.

**Proposed fix:** Amend §17.3 to define layout `fill` explicitly, e.g.: "`fill` requests that the container occupy the full available extent of its MAIN axis (width for `row`, height for `column`); the cross axis remains intrinsic. `fill` defaults to `false`. Use `fill_fraction` for a partial-width request and `weight` to divide a parent's remaining main-axis space. When `scroll` is also true, `fill` applies to the scrolling axis's viewport, not to the scrolled content." Project the resolved semantics into contract.json alongside the existing `fill_fraction` entry.

## [P2] [unverified] §17.3 / §17.5 / §16.3 — Out-of-vocabulary enum VALUE behavior is specified for `text.style` alone, so implementations split between rejecting and defaulting

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:660  
**SPEC line:** 1806  
**Auditor:** Audit SS17.4 through SS17.6 (layout nodes, the scaffold and its slots,

**SPEC quote:**
> `style` is `body` (default), `title`, `headline`, `caption`, `label`, or `mono`; unknown values fall back to `body`. … `box.alignment` is one of `top_start`, `top_center`, `top_end`, `center_start`, `center`, `center_end`, `bottom_start`, `bottom_center`, or `bottom_end`; the default is `top_start`. `surface.shape` is `rounded`, `rounded_small`, or `circle`; omission is rectangular. … `chart.kind` is `line` (default), `bar`, `area`, or `sparkline`.

**Detail:** §17.2 states a fallback for exactly one enumerated member (`text.style`: "unknown values fall back to `body`") and §17.5 states a skip rule for exactly one more (an unknown canvas `op`). Every other enumerated member in §17.3/§17.5 — `row.align`, `column.align`, `flow_row.align`, `arrange`, `box.alignment`, `surface.shape`, `chart.kind`, `table.aligns` entries — enumerates its values and stops. §16.3 governs unknown FIELDS ("A Companion MUST ignore an unknown optional node field"), not unknown values of a known field, and §16.1 makes "a malformed node" a whole-surface 1201 without saying whether an out-of-vocabulary enum value makes a node malformed. §24.6 item 13 then REQUIRES a conformance suite to cover "unknown node, field, enum, builtin, capability, trigger, and predicate behavior" — an assertion no one can write. The reference implementation shows the split inside a single file: SpecValidator rejects an unknown `table.aligns` entry with 1201 (SpecValidator.kt:660-664) — the one member contract.json does NOT project as an enum — while silently defaulting every member contract.json DOES project (`box.alignment` → top_start, LayoutNodes.kt:186-196; `surface.shape` → rectangular, 208-213; `align`/`arrange` → default, 96-116, 130-134; `chart.kind` → line, VisualizationNodes.kt:148-176).

**Failure scenario:** Emacs emits `{"t":"table","rows":[…],"aligns":["start","right"]}` (a plausible typo for `end`). This Companion rejects the ENTIRE surface with 1201 content-invalid, so a document whose only defect is one alignment token blanks the whole screen — while the byte-adjacent `{"t":"box","alignment":"right"}` is accepted and silently rendered top_start. A second Companion could reasonably invert both choices, and neither behaviour is refutable against the SPEC.

**Proposed fix:** Add a general rule to §17.1: "Unless a member's row states otherwise, a value outside a listed enumeration MUST be treated as if the member were omitted — the receiver applies the stated default and MUST NOT reject the containing document. A member whose row states an explicit rejection rule (for example `TableRow.kind`, whose unknown value makes the table invalid) keeps that rule." Then make SpecValidator's `aligns` check a fallback rather than a 1201, and project the resolved rule into contract.json's `enums` block.

## [P2] [unverified] §17.7 — §17.7 never defines how ${selection} and ${cursor} interact with line-start and block placement

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/ToolbarEdits.kt`:102  
**SPEC line:** 2145  
**Auditor:** Audit SS17.7 (editor toolbar: snippets, substitution tokens, placement

**SPEC quote:**
> | `${selection}` | Current selection; substituted text remains selected |
| `${cursor}` | Final cursor position marker |
… It MAY contain `placement` (`cursor`, `line-start`, or `block`)

**Detail:** The placeholder table is written for the default `cursor` placement — 'substituted text remains selected' and 'final cursor position' presuppose that the insertion replaces the selection at the caret. §17.7 says nothing about the other two placements: whether a `${selection}` snippet under `line-start`/`block` CONSUMES the selection (moves it) or COPIES it (duplicating the text), and whether `${cursor}` still governs the final caret when the insertion point is not the caret. The reference resolves the three cases inconsistently and silently: applySnippet dispatches to insertAtLineStart (ToolbarEdits.kt:102), which takes only the rendered string, drops r.cursor and r.selStart/selEnd entirely and returns a bare caret; insertBlock (line 145-158) honors r.cursor but never deletes the selection; only insertAtCursor (line 112-127) consumes the selection. An implementer reading the table alone would just as reasonably wrap the selection in place for all three, or keep the selection selected after a block insert. Interop breaks per-Companion for the single most common org toolbar item.

**Failure scenario:** Text "foo bar" with "foo" selected (0..3) and item {label:"Quote",snippet:"> ${selection}",placement:"block"}. The reference produces "> foo\nfoo bar" with a collapsed caret — the selection is DUPLICATED, not quoted. A Companion reading the table as 'the selection is substituted' produces "> foo\n bar" with "foo" still selected. Same authored toolbar, two different documents. With placement:"line-start" and snippet "TODO ${cursor}" the reference silently ignores ${cursor} and leaves the caret at its shifted original column, while a table-faithful implementation places it after "TODO ".

**Proposed fix:** Amend §17.7's placement sentence: state that a snippet's `${selection}` consumes the current selection under EVERY placement (the selected range is removed and re-emitted inside the snippet, remaining selected), that `${cursor}` determines the final caret under every placement and takes precedence over `${selection}` when both are present, and that when a snippet contains no position token the caret ends immediately after the inserted text (for `line-start`, after the inserted prefix). Name the no-selection case explicitly: `${selection}` with a collapsed caret substitutes the empty string and the caret lands at that point.

## [P2] [unverified] §17.7 — §17.7 leaves line operations undefined for a non-collapsed or multi-line selection

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/ToolbarEdits.kt`:164  
**SPEC line:** 2172  
**Auditor:** Audit SS17.7 (editor toolbar: snippets, substitution tokens, placement

**SPEC quote:**
> A `line` operation is a Companion-local structural edit of the line containing the cursor. … `move-up` exchanges the cursor's line with the line above it, keeping the cursor at the same column of that line, and MUST be a no-op on the first line

**Detail:** Every line op is specified against 'the cursor's line'. §17.7 never says (a) which end is 'the cursor' when a selection is active — §19.3 only guarantees `cursor` equals ONE end — (b) whether an op acts on all lines a multi-line selection touches, which is the near-universal editor convention for promote/demote/move (and org-metaup/org-shiftmetaright behavior an org app will expect), or (c) whether the selection survives the op. The reference silently picks the anchor and discards the selection: lineOp is handed `ToolbarEdit(text, selection.start, selection.end)` (EditorToolbar.kt:82) and every op uses `edit.selStart` as the cursor (ToolbarEdits.kt:183, 200, 220, 236) and returns `ToolbarEdit.caret(...)`, collapsing the selection. For a Compose backward selection selStart is the LATER offset, so the op silently targets a different line than the visible caret.

**Failure scenario:** The user selects three org headings (offsets 10..80, dragged upward so Compose reports TextRange(start=80,end=10)) and taps {icon:"demote",line:"demote"}. The reference demotes only the line containing offset 80 — the BOTTOM line, opposite the visible caret — and collapses the three-line selection to a caret, so a second tap cannot repeat the gesture. A Companion that read 'the cursor's line' as the active end would demote the top line; one following editor convention would demote all three and keep them selected. All three are defensible under the current text.

**Proposed fix:** Amend §17.7's line-op paragraph: define 'the cursor's line' as the line containing the caret (the active end, i.e. the position an endpoint would report as `cursor`), state that when the selection is non-collapsed and spans more than one line the operation applies once to EVERY line the selection intersects (promote/demote per line; move-up/move-down move the whole block, no-op when the block touches the first/last line), and require the selection to be preserved across the block it covered so the gesture is repeatable. If a single-line-only reading is intended, say instead that the selection is collapsed to the caret before the op.

## [P2] [unverified] §17.7 — §17.7 never fixes the schema of a toolbar item's `long_press`: label requirement, own vs inherited `placement`, and nesting are all undefined

**SPEC line:** 2137  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 14 th

**SPEC quote:**
> It MAY contain `placement` (`cursor`, `line-start`, or `block`) and
`long_press`, which contains exactly one non-menu operation. A Companion MUST
reject an item with zero or multiple primary operations.

**Detail:** §17.7:2127 defines a ToolbarItem as "MUST contain `label` or `icon` and exactly one operation". §17.7:2137-2139 then introduces `long_press` as something that "contains exactly one non-menu operation" — without saying whether `long_press` IS a ToolbarItem. Three consequences are left open. (1) Label requirement: must `long_press` carry `label` or `icon`? A long-press has no independent affordance to label, so the natural authoring is `{"snippet":"* "}`; but if `long_press` is a ToolbarItem, that object is invalid and §16.1:1681-1684 requires rejecting the ENTIRE surface with `1201`. (2) Placement: `placement` is defined as a member of the item, and the SPEC never says whether a `long_press` may carry its own `placement` or inherits the parent item's. (3) Nesting: nothing forbids `long_press` inside `long_press`, so under the ToolbarItem reading the structure recurses to §4.5's depth-64 limit. The reference implementation resolved all three by fiat in the maximal direction — /home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-2/companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt:863-866 calls `validateToolbarItem(lp, …)` recursively, which enforces label-or-icon at :824-825, accepts a per-object `placement` at :861, and permits unbounded `long_press` nesting — while the renderer at companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/EditorToolbar.kt:88,112,148 reads `placement` off the long_press object itself, defaulting to `cursor` and NOT inheriting the parent's.

**Failure scenario:** Emacs authors a bullet button: `{"icon":"list","snippet":"- ","placement":"line-start","long_press":{"snippet":"1. "}}`. Companion A (the reference reading) rejects the containing `editor` node — and therefore the entire `surface.update` — with `1201 content-invalid` because the `long_press` object has neither `label` nor `icon`; the screen never renders. Companion B (operation-holder reading) accepts it, and long-press inserts `"1. "` at the caret's line start, inheriting `placement`. Companion C accepts it but applies the default `cursor` placement, inserting `"1. "` mid-word. Same authored toolbar, three outcomes: whole-surface rejection, correct list conversion, and corrupted text.

**Proposed fix:** Amend §17.7 to state that `long_press` is a closed SECONDARY-OPERATION object, not a ToolbarItem: it MUST contain exactly one non-menu operation member (`snippet`, `on_tap`, `command`, or `line`); it MUST NOT contain `label`, `icon`, `menu`, or a nested `long_press` — any of those makes the item invalid; and it MAY contain its own `placement`, which when absent inherits the containing item's `placement` (which itself defaults to `cursor`). State the same rule for `menu` sub-items if their schema differs. Project the secondary-operation object into `contract.json` alongside `toolbar.ops`.

## [P2] [unverified] §18.4 — §18.4 never says what "legible platform fallback" is legible AGAINST, so follow-system polarity combined with a mirrored opposite-polarity palette yields ~2:1 contrast for every un-pushed role

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/ThemeModel.kt`:130  
**SPEC line:** 2296  
**Auditor:** Audit SS18.4 (theme.set, color roles, dark tri-state/follow-system fro

**SPEC quote:**
> Every field is optional. The Companion MUST merge missing roles with a legible platform fallback, MUST persist the latest accepted theme, and MUST treat each notification as a complete replacement of the previously pushed values. When a role is present but its paired on-color is absent (for example `primary` is pushed without `on_primary`), the Companion MUST derive a contrast-legible on-color from the pushed color rather than adopt its base scheme's on-color, which need not be legible against the foreign pushed color.

**Detail:** Amendment #56 fixed exactly one axis of this problem — the on-color paired with a pushed base role — and the reference implements it (ThemeModel.kt:67-71). But the identical hazard on the base-role axis and the syntax-fallback axis is left undefined. §18.4 makes `dark` (or its omission) and `colors` fully independent (lines 2304-2311 explicitly bless follow-system + mirror-Emacs as a combination), yet the merge rule names no reference background for "legible". Two conformant readings: (a) legible means "the platform's own default for that role at the selected polarity" — the reference's reading, ThemeModel.kt:130 selects `darkColorScheme()`/`lightColorScheme()` from `dark` alone and ThemeModel.kt:135 passes the same polarity flag to `SyntaxColors.forBackground(dark)`; (b) legible means "legible in the RESULTING merged scheme", i.e. against the merged `surface`/`background`, which requires deriving the fallback polarity from the pushed surface luminance when `dark` is omitted. Reading (a) is internally inconsistent in the reference itself: SyntaxHighlight.kt:3-5 claims the palettes are "keyed only on surface luminance so they stay legible on any scheme", but the call site passes the polarity flag, not the pushed surface. The SPEC gives an implementer nothing to choose between them.

**Failure scenario:** A user with a dark Emacs theme picks follow-system polarity + mirror-Emacs colours (the exact combination amendment #36 exists to express) and carries the phone in light mode: `theme.set {"colors":{"surface":"#2E3440","background":"#2E3440","on_surface":"#D8DEE9"}}` with `dark` omitted. `dark` = isSystemInDarkTheme() = false, so the base is `lightColorScheme()`. `primary` was not pushed, so it merges to the light default #6750A4 on the pushed #101018/#2E3440 surface: contrast ≈ 2.9:1 — below the 3:1 floor for even large text. Worse, the whole syntax fallback comes from `SyntaxColors.forBackground(false)`: the light `string` colour #4F6F3F on the pushed #2E3440 editor background is ≈ 2.2:1, so every string literal in a code buffer is effectively unreadable. Each un-pushed role is individually a "legible platform fallback" under reading (a) and illegible under reading (b).

**Proposed fix:** Amend §18.4 after the amendment-#56 sentence: state that the reference background for legibility is the merged `surface` (or `background` where that role governs the drawing), and require the Companion to select every un-pushed role's fallback — including the syntax fallback palette — against that merged background rather than against `dark` alone. Equivalently, require that when `dark` is omitted and `colors` supplies `surface`/`background`, the fallback polarity be derived from that colour's luminance while the system setting still governs any un-mirrored chrome. Record the two readings and name the winner so a Companion cannot ship reading (a) and claim conformance.

## [P2] [unverified] §18.5 — §18.5 never defines what `channel` means, so `channel` and the amendment-#59 priority-monotonicity MUST are irreconcilable on a channel-importance platform

**SPEC line:** 2336  
**Auditor:** Audit SS18.5 (notification surfaces: meta, priority monotonicity amend

**SPEC quote:**
> A `notification:*` surface metadata object MAY contain `channel: identifier`, `ongoing: boolean`, `category: identifier`, `priority`, `chronometer`, and `actions`. ... `priority` is a best-effort hint: the Companion MUST present it monotonically (never below the requested level relative to `default`) and MAY coalesce adjacent levels — notably `high` and `max` — where the platform lacks a distinct level; authors MUST NOT rely on a five-way distinction.

**Detail:** `channel` is introduced as a bare `identifier` and then never mentioned again anywhere in the SPEC (it appears once in contract.json's notification_meta.fields list and nowhere else). Amendment #59 was written against Android channel importance but did not resolve the structural collision that platform creates: a NotificationChannel owns the importance, its importance is immutable after creation, and it is thereafter user-owned. Two mutually incompatible readings are both defensible. (a) `channel` names one platform channel 1:1 — then the FIRST priority posted on that channel freezes its importance forever, and a later priority:"high" on the same channel cannot be presented above the level the first post created, directly violating the monotonicity MUST. (b) The platform channel is the product (channel x priority) — what the reference does (Notifications.channelFor, Notifications.kt:128-141, mints "ebp:<channel>:<priority>"). Reading (b) satisfies monotonicity but destroys the only user-facing meaning channel could have: a user who mutes "ebp:agenda:default" still gets "ebp:agenda:high" alerts, up to five settings entries accumulate per authored channel, and nothing deletes stale ones. Separately, the monotonicity MUST has no user-override carve-out at all: once the user lowers or mutes a channel, NO conformant presentation is possible, so the MUST is unsatisfiable on the platform it was written for.

**Failure scenario:** Emacs posts `notification:agenda` with {channel:"agenda", priority:"default"}, then later the same surface with {channel:"agenda", priority:"high"}. Under reading (a) the second post is presented at IMPORTANCE_DEFAULT — below the requested level — violating the MUST. Under reading (b), which the reference implements, the user who previously muted the "EBP default" channel to stop agenda noise is alerted anyway by a second channel named "EBP high", silently defeating their mute. Two conformance suites written against the two readings would score the same Companion pass and fail.

**Proposed fix:** Amend §18.5 to (1) define `channel` normatively as a stable user-visible grouping key for platform-level notification preferences and require the Companion to map one authored channel to at most one user-facing preference grouping; (2) state that `priority` selects presentation WITHIN that grouping where the platform permits, and that where the platform binds importance to the grouping the Companion MUST use the highest priority the surface has requested for that channel and MAY recreate the grouping on an increase; and (3) add the missing carve-out — the monotonicity requirement governs the Companion's own presentation decision and is subordinate to an explicit user preference for that channel or app, which the Companion MUST NOT override.

## [P2] [unverified] §19.3/§19.4 — §19 defines no recovery when the once-only resynchronization is itself refused, leaving a receiver permanently STALE with no legal exit

**SPEC line:** None  
**Auditor:** Audit emacs/ebp.el as a whole against every SPEC duty assigned to "a c

**SPEC quote:**
> On any failure it MUST mark the
session stale and MUST request resynchronization once; it MUST ignore further
deltas until the resynchronization completes.

**Detail:** §19.3 (SPEC line 2564-2566) obliges a receiver whose delta failed to mark the session stale, request resync exactly ONCE, and ignore further deltas "until the resynchronization completes". §19.4 (SPEC line 2637-2639) simultaneously provides that "An unknown or `CLOSED` tuple MUST receive `1201 content-invalid` with `data.reason: \"editor-stale\"` and MUST NOT create a new session." These two rules intersect on a reachable race — a delta failure concurrent with node removal / surface tombstoning, both of which §19 requires to close the session — and the document never says what happens next. §19.2's state set is exactly OPEN, STALE, CLOSED with no 'resync-pending' state, so 'the resynchronization completes' has no defined negative outcome. Three incompatible readings are permitted: (a) a refused resync ends the ignore-deltas window, so the next failing delta may resync again (contradicts "once"); (b) the receiver must locally transition the session to CLOSED and fall back to the cached snapshot's authored `value` (the §19 transport-loss rule, but never stated for this case); (c) the session stays STALE indefinitely, ignoring all deltas, until an explicit `edit.close` or transport loss (a permanent local wedge). The reference implementation picks none: `ebp-client-edit-resync`'s callback is `(unless error …)` (emacs/ebp.el:1077-1084), so the refusal is discarded and the `editors` entry survives holding a dead `:session` and stale `:text`.

**Failure scenario:** Emacs's mirror is at seq 4 when `edit.delta` seq 5 fails its length check. Emacs sends `edit.resync` naming session S1. Concurrently the Companion removes the `editor` node from the surface, closes S1, and sends `edit.close`. It then answers the resync with `1201 content-invalid`/`editor-stale` and creates no new session. Under reading (c) — and in the reference impl — `ebp-client-editor-text` keeps returning the pre-failure text for a session that no longer exists, and any `ebp-client-edit-apply` the application issues names the dead session and is answered `stale`, which the impl's `when` at emacs/ebp.el:1059 silently drops. The editor is permanently and invisibly dead with no protocol event marking it so.

**Proposed fix:** Amend §19.3 to name the negative outcome explicitly: "A resynchronization request answered with `1201 content-invalid` and `data.reason: \"editor-stale\"` completes the resynchronization unsuccessfully. The receiver MUST then treat the session as `CLOSED`, discard its shadow, and fall back to the cached snapshot's authored `value` exactly as it would after transport loss. A subsequent `edit.open` for the same presentation identity begins a new session." Add the symmetric sentence to §19.4 after the unknown/CLOSED-tuple rule, and extend §19.2's transition list with "a refused `edit.resync` makes the requester's session `CLOSED`".

## [P2] [unverified] §19.5 / §22.2 — §19.5 and §22.2 both key annotation conflation on (editor, sequence) with no method component, permitting cross-method annotation loss

**SPEC line:** 2681  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 14 th

**SPEC quote:**
> These methods are latest-wins per editor and sequence;
they MUST NOT delay text synchronization.

**Detail:** §19.5 defines three distinct, non-overlapping annotation channels — `diagnostics.show`, `fontify.show`, `eldoc.show` (all Emacs→Companion notifications per §11:945-947) — carrying wholly different payloads (`diagnostics`, `runs`, `text`). §19.5:2681 states they are "latest-wins per editor and sequence", and §22.2:3285-3288 authorizes a sender to conflate them: "Surface snapshots waiting locally to be sent, theme replacements, and editor annotations MAY be conflated by key. A sender SHOULD retain at most one unsent snapshot per surface and one unsent annotation per editor and sequence." Neither sentence names the METHOD as part of the conflation key. Under the literal reading the key is `(editor_id, session, seq)`, so a pending `diagnostics.show` is displaced by a later `fontify.show` for the same sequence — two payloads with no replacement relationship. Under the intended reading the key is `(method, editor_id, session, seq)`. §22.2's class-2 rule does not rescue this: annotations are explicitly assigned to class 1, and class 2 enumerates only "Editor opens, deltas, applies, carets, closes, and resynchronizations". §22.2:3303-3305 ("A receiver MUST NOT claim to discard an obsolete frame 'without parsing' when the conflation key exists only inside that frame") governs receivers, not this sender-side key definition.

**Failure scenario:** Emacs finishes a check pass at `seq: 7` and queues, in order, `diagnostics.show` (three errors), `fontify.show` (400 runs), and `eldoc.show` (signature text) while the outbound socket is backpressured. A sender implementing §22.2's literal key retains only the last unsent annotation for `(editor, 7)` and transmits `eldoc.show` alone. The Companion never receives the diagnostics or the fontification; the editor shows no error underlines and no syntax coloring, and because §19.5's latest-wins model has no acknowledgement or resend rule, nothing ever repairs it until the next text change advances `seq`. A sender keying on method sends all three. Both claim conformance to the same sentence.

**Proposed fix:** Amend §19.5:2681 to read "These methods are latest-wins per method, editor, and sequence" and amend §22.2's class-1 bullet to "one unsent annotation per method, editor, and sequence", so the conflation key is explicitly `(method, document, editor_id, session, seq)`. While amending §19.5, also settle the companion asymmetry: §19.1:2476-2477 says the identifying tuple is `(document, editor_id, session)`, but the three annotation params objects at §19.5:2669-2678 omit `document`. State whether `document` is REQUIRED (making the tuple uniform with every other §19 message), or OPTIONAL-and-ignored because `session` is already globally unique per §19.1:2478-2480.

## [P2] [unverified] §20.1 — SPEC never defines which error a capability-gated method receives when its capability was not granted; §8's 1001 gloss and §7.3's -32601 are both readable

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1064  
**SPEC line:** 2726  
**Auditor:** Audit SS20 (device capability module) against CapabilityCatalog.kt, Co

**SPEC quote:**
> `caps` is the exact Section 20 capability catalog supported by the Companion;
`capability.invoke` remains unavailable unless `capabilities` was granted.

**Detail:** §20.1 says capability.invoke "remains unavailable" without naming the wire error. §11 (SPEC.md:917-948) gives every method a "Capability" column but states no error rule for an ungranted gate. §7.3 (SPEC.md:505-506) covers only "An unknown request MUST receive `-32601 Method not found`" — and capability.invoke is a *known* method in a registry both peers can read, so calling it unknown is a choice, not a deduction. Meanwhile §8's error table (SPEC.md:558) defines `1001 cap-unsupported` as "Capability was not advertised or is unavailable" — the word "unavailable" is the same word §20.1 uses, which makes 1001 an equally defensible answer. A third reading is `1204 session-state`, since the grant is a session property. The reference implementation picked -32601 uniformly (CompanionEngine.kt:1064 for capability.invoke, and identically at 870 reminders.set, 1004 triggers.set, 1209/1253 edit.apply/resync, 1403 dialog.show), while for an ungranted *surface namespace* it picked a fourth answer, `1201 content-invalid` with reason "namespace-not-granted" (CompanionEngine.kt:577-579) — the internal inconsistency is itself evidence the SPEC does not settle this. contract.json's capability.invoke entry lists errors [1001, 1002, 1003, -32602] and does not include -32601, so a conformance suite generated from the projection would not even expect the answer the reference gives.

**Failure scenario:** Emacs requests wants=[] (or a Companion that does not support `capabilities` grants nothing) and the application nevertheless calls capability.invoke. Companion A (this reference) answers `-32601 method-not-found`; Companion B, reading §8's 1001 row, answers `1001 cap-unsupported`. An Emacs client that branches on the code — retry-after-renegotiate on 1001 versus permanent-unsupported on -32601 — behaves differently against two conformant Companions, and no Golden or contract entry can adjudicate.

**Proposed fix:** Amend §7.3 (or add a sentence to §11 under the Capability column) stating the single normative answer, e.g.: "A request naming a method whose capability gate was not granted MUST receive `-32601 Method not found`; the method is treated as not existing in that session. A notification whose capability gate was not granted MUST be logged and ignored." Then add a matching sentence to §13.1 so an ungranted surface namespace's `1201 content-invalid` is explicitly the deliberate exception (it is a params-content gate, not a method gate), and add `-32601` to each gated method's `errors` list in contract.json.

## [P2] [unverified] §20.1 — "canonical size under Section 4.5" is undefined for the device report — §4.5 scopes its JCS encoded-size definition to only two named limits

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1643  
**SPEC line:** 2738  
**Auditor:** Audit SS20 (device capability module) against CapabilityCatalog.kt, Co

**SPEC quote:**
> The complete device report's canonical size under Section 4.5 MUST NOT exceed
`limits.max_device_report_bytes`. A Companion whose full catalog would exceed
that bound MUST advertise a bounded subset that fits; it MUST NOT emit a device
report that depends on truncation.

**Detail:** §20.1 defers the device report's size units to §4.5, but §4.5's only definition of encoded size is explicitly scoped to two other limits: "For `max_field_bytes` and `max_input_state_bytes`, encoded size means the UTF-8 length of the logical value serialized by the JSON Canonicalization Scheme [RFC8785]" (SPEC.md:215-217). Nothing in §4.5 defines "canonical size" for an object governed by `max_device_report_bytes`, even though its own table row (SPEC.md:240) reuses the phrase "maximum canonical bytes of the complete device report". §2.2 further muddies it: "Tests of JSON message semantics MUST compare parsed JSON values unless this document expressly requires a canonical serialization" — so it is unclear whether the report must be JCS-canonicalized for measurement at all, or merely measured in whatever encoding the Companion emits. Divergent readings an implementer must pick among: (a) the UTF-8 length of the RFC8785 canonicalization of the report object (member-sorted, minimal escapes); (b) the UTF-8 length of the report as this Companion actually serializes it; (c) the length of the report's contribution to the welcome body including the `"device":` key. Reading (a) and (b) diverge whenever escaping or number formatting differ. The reference chose (b): `config.deviceReport.toString().toByteArray(Charsets.UTF_8).size` (CompanionEngine.kt:1643) — org.json's non-canonical serializer, insertion-ordered, with org.json's own escaping choices.

**Failure scenario:** Two Companions advertise the same logical device report containing a package name with a `/` and a non-BMP label. Companion A measures the RFC8785 canonicalization (which escapes only what RFC8259 requires) and finds 8,180 bytes, under an 8,192 budget, and emits it. Companion B uses a serializer that escapes `/` as `\/` (permitted by RFC8259 and produced by several JSON libraries) and measures 8,240 bytes, so it drops entries to fit. The same report is conformant for one and over-limit for the other, and neither can be shown wrong. A conformance suite cannot write a Golden that pins the boundary case.

**Proposed fix:** Amend §4.5 to widen the definition sentence from two limits to all size-bounded objects, e.g.: "For `max_field_bytes`, `max_input_state_bytes`, and `max_device_report_bytes`, encoded size means the UTF-8 length of the logical value serialized by the JSON Canonicalization Scheme [RFC8785]." Keep the following sentence's obligation ("the Companion MUST use a representation no longer than that value's JCS representation") and extend it to the device report so the emitted bytes can never exceed the measured budget. Optionally state explicitly that the `"device"` member name and its colon are counted in the §4.5 welcome reservation but not in `max_device_report_bytes`.

## [P2] [unverified] §21.2 — §21.2 mandates a single transaction spanning the event record and the registration-state records, but defines no obligation when they are separate durable resources

**SPEC line:** 2972  
**Auditor:** Audit SS21 (device trigger module) end to end — SS21.1 trigger.set rep

**SPEC quote:**
> 3. durably commit the new throttle state, any one-shot completion or
   boot-generation receipt, and, for `queue` or `wake`, the complete event
   record and `queue_seq` in one transaction;

**Detail:** "in one transaction" reads as a hard atomicity requirement over two logically distinct durable objects: the queue record (§15, keyed by `queue_seq`) and the registration's runtime records (§21.1's throttle floor / one-shot marker / boot receipt / schedule anchor). Nothing in §15 or §21 says these must live in one store, and a real Companion has strong reasons to keep them apart (the queue is per-identity FIFO with expiry sweeps; registration state is per-registration). §21.4 then tacitly concedes that crashes mid-transaction happen — "Because a crash can occur after a platform side effect but before its progress marker, local effects MAY repeat at that boundary" and "Recovery MUST eventually clear `pending-local`" — but the recovery paragraph is scoped entirely to the LOCAL list; it says nothing about reconstructing the exactly-once markers that step 3 was supposed to have committed atomically. Two implementers therefore diverge legitimately: (a) reading "one transaction" literally, a Companion must co-locate the event queue and registration state in one atomically-replaced object; (b) reading it as an effect requirement, a Companion may use a compensating two-phase commit plus a restart-time reconstruction pass — but the SPEC then never says WHICH markers must be reconstructible or from what. The reference took reading (b): `TriggerFiringService.admit` commits A then B with rollback, and `recover()` reconstructs throttle + one-shot + every_s from surviving queued records. Both audited defects above are the direct consequence of the SPEC leaving reading (b) unspecified: nothing told the implementer to reconstruct the boot receipt, and nothing told it that reconstruction must be scoped to the registration generation that produced the record.

**Failure scenario:** Two conformance-claiming Companions, both passing a §24.6 module suite: Companion X co-locates queue+registration state and survives a crash between admission and marker commit with zero duplicates; Companion Y uses compensating A/B commits and, after the same crash, re-admits the occurrence on restart because it reconstructs no marker at all — and can cite §21.2's silence on recovery as license. Emacs sees the same trigger fire twice with two distinct EventIds, defeating §21.5's "MUST NOT create another occurrence" with no SPEC text to appeal to.

**Proposed fix:** Amend §21.2 after the five-step list: explicitly permit implementing step 3 as a compensating two-phase commit provided that (i) the remote event record is committed first and MUST be deleted if the registration-record commit fails, and (ii) at process start, before any source may admit a new occurrence, the Companion MUST reconstruct from every surviving durable event record ALL of that registration's exactly-once state — throttle floor, one-shot completion, repeating last-fire floor, and boot-generation receipt — and MUST NOT apply a reconstructed record to a registration that was changed or re-added after that record was admitted (require the durable event record to carry the registration's acceptance generation for this purpose). Add a §24.6-style module test case: crash between the event commit and the record commit, restart, assert no duplicate occurrence.

## [P2] [unverified] §21.4 — §21.4 requires substitution to always produce a string, making `${data.FIELD}` unusable for any typed capability argument, with install-time validation left undefined

**SPEC line:** 3049  
**Auditor:** Audit SS21 (device trigger module) end to end — SS21.1 trigger.set rep

**SPEC quote:**
> Substitution MUST be single-pass and MUST always produce a string. Numbers and
booleans use their JSON spelling. Missing or null values leave the token
literal.

**Detail:** §20.3 capability Args are a closed, TYPED schema — `vibrate` takes `{ms}` as an integer 1..60000 or `{pattern}` as an array of integers; `volume.set` takes an integer; `tts.speak` takes a string. §21.4 simultaneously requires (i) "The Companion MUST validate every entry when installing the set" and (ii) that a substitution "MUST always produce a string". Those two rules cannot both be honored for a numeric or boolean Arg: at install time `{"cap":"vibrate","args":{"ms":"${data.level}"}}` has a string where the schema demands an integer, and after substitution it is `"19"` — still a string. So either the entry must be rejected at install (making `${data.…}` legal only for string-typed Args, which the SPEC never states) or it must be accepted and then fail at fire time (which contradicts the point of install-time validation). The SPEC also never says whether "validate every entry" includes the §20.3 Args schema at all, or only the `{cap,args?}` / `{notify:{title?,text}}` shape. The reference implementation resolved it by validating only the shape at install (TriggerValidator.kt:336-337) and the schema at fire time (TriggerFiringService.kt:209), where a failure is a silent no-op — a client is told its trigger is armed while its local response is permanently dead.

**Failure scenario:** An author writes `{"id":"low-batt","type":"battery.level","params":{"below":20},"on_fire":[{"cap":"vibrate","args":{"ms":"${data.level}"}}]}`. Companion A rejects the set with 1101 (`args.ms` must be an integer). Companion B accepts it with `{count:1}` and silently never vibrates. Companion C accepts it and coerces `"19"` back to 19 at fire time, vibrating for 19 ms. All three can cite the current text; the author has no portable way to feed fire data into a numeric capability argument at all.

**Proposed fix:** Amend §21.4's substitution paragraph to state either (a) a token that constitutes the ENTIRE string value adopts the JSON type of the substituted fire-data member (number stays a number, boolean stays a boolean) while an embedded token still yields a string — which makes `${data.level}` usable for `vibrate.ms` — or (b) substitution applies only where the §20.3 Args schema declares a string, and any `${…}` token in a non-string-typed Arg MUST reject the replace-set at install. Whichever is chosen, add an explicit sentence that "validate every entry" includes running the §20.3 Args schema for each `{cap,args}` entry at install time, and that a §20.3 Args failure at fire time is a `21.4` runtime failure recorded as a diagnostic.

## [P2] [unverified] §21.5 — §21.5 never defines what happens to a `time` occurrence whose gate/throttle blocks it or whose durable transaction fails

**SPEC line:** 3134  
**Auditor:** Audit SS21 (device trigger module) end to end — SS21.1 trigger.set rep

**SPEC quote:**
> `time.at_ms` names an absolute wall-clock
instant; a pending one-shot fires when the effective wall clock (Section 15.2)
first reaches or passes it.

**Detail:** §21.2 says "A failed gate or throttle check MUST NOT consume throttle state, execute local responses, or create an event" and "If the durable transaction fails, the Companion MUST NOT execute local responses or claim remote admission" — so a `time` occurrence that fails eligibility leaves the registration exactly as it was. For every other trigger type that is harmless: the source will produce another observation. For `time` the source IS the clock, and §21.5 defines the firing instant as a single point (`first reaches or passes it`) with a completion marker committed only "On admission of its first eligible occurrence". The SPEC never says which of these holds: (a) the occurrence is lost and the one-shot stays armed but has no defined future firing instant, so it may never fire again (a `drop`-policy one-shot whose gate was false at `at_ms` is dead); (b) the one-shot remains pending and MUST be re-evaluated, in which case the SPEC gives no cadence, no bound, and no interaction with §23.5's exhaustion rules. The same hole exists for `every_s`: §21.5 says the cadence "MUST then resume on the original anchor + k·interval grid" but never says whether a boundary that was reached and then blocked by the gate counts as consumed, or must be retried before the next boundary. The reference implementation picked reading (b) with a zero-length retry interval, which is why it spins (see the at_ms finding above); a different implementer reading (a) would silently never fire the trigger. Both are defensible under the current text.

**Failure scenario:** Emacs registers `{"type":"time","params":{"at_ms":T},"when":[{"type":"battery.level","above":50}],"policy":"drop"}` and battery is at 30% at instant T. Companion A (reading (a)) never fires it, ever — Emacs's one-shot silently vanishes. Companion B (reading (b), the reference) re-evaluates immediately and forever, burning wakeups until the battery crosses 50%. Both claim §21 conformance; Emacs cannot write a portable trigger.

**Proposed fix:** Amend §21.5's `time` paragraph: state that a `time` occurrence blocked by its state gate, its throttle, or a failed durable transaction is NOT admitted and does not commit a completed marker, that a one-shot `at_ms` MUST remain armed and be re-evaluated on a bounded schedule (implementation-chosen but at most once per minute, and it MUST NOT re-evaluate more often than once per its own retry floor), and that a blocked `every_s` boundary is consumed — the next evaluation occurs at the next `anchor + k·interval` boundary, never before. Add the symmetric statement for `boot` (a blocked boot occurrence stays eligible for the same generation until admitted).

## [P2] [unverified] §21.5 / §21.6 — §21.5 leaves the value domain and meaning of `state.edge` fire data `edge` undefined

**SPEC line:** 3083  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 14 th

**SPEC quote:**
> | `state.edge` | `{when,edge?}` | `{holds,edge}` | Convert an advertised trackable-state conjunction into `rise`, `fall`, or `both` edges. |

**Detail:** The catalog row names `edge` in both the Params column and the Fire-data column, and its Normative-behavior text ("into `rise`, `fall`, or `both` edges") describes the PARAMETER. §21.6:3180-3181 defines only the parameter's domain: "`edge` defaults to `rise` and is `rise`, `fall`, or `both`." Amendment #45 (§21.5:3103-3105) made every unmarked Fire-data member REQUIRED-present but said nothing about its VALUE: "Every member shown in a type's Fire-data column is REQUIRED in that occurrence's `args.data` … a Companion that admits an occurrence for a type MUST populate its required fire-data members." So for `params.edge: "both"` the SPEC never says whether `args.data.edge` reports the OBSERVED direction (`rise` or `fall`, never `both`) or ECHOES the configured parameter (`both`). Every other catalog row pins its fire-data enums in the Normative-behavior column (`power`: "State is `connected` or `disconnected`"; `network`: "Event is `available` or `lost`") — `state.edge` is the one row that does not. The reference implementation chose the observed-direction reading without a governing sentence: /home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-2/companion/wire/src/main/kotlin/com/calebc42/ebp/wire/TriggerRuntime.kt:226-227 emits `.put("edge", if (holds) "rise" else "fall")`.

**Failure scenario:** Emacs registers `{"id":"desk","type":"state.edge","params":{"when":[{"type":"power","state":"connected"},{"type":"screen","state":"unlocked"}],"edge":"both"},"policy":"queue","ttl_s":3600}` and dispatches on `args.data.edge` with `(pcase edge ("rise" (start-timer)) ("fall" (stop-timer)))`. Companion A (reference) delivers `{"holds":false,"edge":"fall"}` and the timer stops. Companion B echoes the configured value and delivers `{"holds":false,"edge":"both"}`; the `pcase` falls through, the timer never stops, and no error is raised anywhere — the event was accepted and its record deleted. Both Companions satisfy every current sentence of §21.5 and §21.6.

**Proposed fix:** Amend the §21.5 `state.edge` row's Normative-behavior column (or add a paragraph after §21.6:3188) stating: "In fire data, `holds` is the conjunction's new truth value and `edge` is the OBSERVED direction of the transition that admitted the occurrence — exactly `rise` when `holds` is `true` and `fall` when `holds` is `false`. `both` is a registration-time selector only and MUST NOT appear in `args.data.edge`." Project the fire-data enum into `contract.json` beside the params enum so the two vocabularies are distinguishable.

## [P2] [unverified] §22.3 — §22.3's `log.error` rate limit is an unquantified MUST — no rate, window, or scope, and amendment #38 already forward-references it

**SPEC line:** 3325  
**Auditor:** Audit SS22 (capability registry and load management: traffic classes, 

**SPEC quote:**
> An endpoint MUST rate-limit `log.error` and MUST NOT allow diagnostic reporting to become an additional overload source.

**Detail:** The sentence imposes a MUST with no measurable content: it names no rate, no time window, and no scope. An implementer cannot tell whether the budget is per connection, per `code`, per `data.kind`, or global to the endpoint; whether it resets on reconnection; whether the 1401 overload diagnostic itself is subject to the same budget (it must be sent exactly once before a mandatory close, so a shared bucket could suppress it); or whether suppression must be silent or must be reported. Amendment #62-era text compounds this: SPEC-CHANGES #38 states that the new §6.2 `1400 frame-too-large` diagnostic is emitted "using §22.3's shape and rate limit" — a normative reference to a rate limit that §22.3 never defines. §24.6 item 14 then requires a conformance suite to include "bounded overload behavior for each traffic class", which cannot be written against an unspecified rate. Divergent conformant readings that a suite would have to accept: (a) one `log.error` per connection lifetime; (b) one per distinct `code` per connection; (c) a token bucket of N/second with unspecified N; (d) unlimited so long as the endpoint's own CPU/memory stays bounded ("not an additional overload source" read as an outcome test rather than a rate test). The reference implementation currently emits with no limiter at three live sites and cites the SPEC while doing so (CompanionEngine.kt:745 comment).

**Failure scenario:** Two conformant Companions face the same peer that sends 10,000 over-limit `pie_menu.show` notifications. Companion A emits 1 `log.error` total (reading (a)); Companion B emits 10,000 (reading (d), arguing 1:1 is not amplification). Emacs, written against A, treats the second `pie-menu-limit` diagnostic as evidence of a protocol fault; against B it drowns. A §24.6 item-14 suite cannot mark either non-conforming.

**Proposed fix:** Amend §22.3 to give the limit measurable content: state the scope (per connection, per `code`), a floor and ceiling (e.g. "MUST NOT emit more than one `log.error` per distinct `code` per second, and MUST NOT emit more than 10 per connection per second in aggregate"), state that suppressed diagnostics are dropped silently (never queued), and carve out the 1401 overload diagnostic so the mandatory pre-close notification can never be rate-limited away. Add a matching sentence to §6.2/amendment #38's `1400` so its forward reference resolves. Then §24.6 item 14 becomes testable.

## [P2] [unverified] §4.2 — §4.2 states number/integer constraints only as sender obligations and never defines the receiver's duty for an out-of-range or non-finite literal

**SPEC line:** 138  
**Auditor:** Audit SS4.1 through SS4.4 (JSON data model: value types, object/duplic

**SPEC quote:**
> An EBP integer MUST be mathematically integral and MUST be in the inclusive range `-9007199254740991` through `9007199254740991`. ... A sender MUST NOT emit a literal that overflows to infinity or whose nonzero exact value underflows to zero. Receivers MUST NOT preserve implementation-specific extra decimal precision as a distinct EBP value.

**Detail:** §4.2's only explicitly receiver-directed sentence is the one about extra decimal precision. Everything else is framed as what an EBP integer/number IS or as what a SENDER must not emit. §6.2's receiver taxonomy covers invalid UTF-8, invalid JSON, and non-object top levels — an RFC 8259-legal literal such as `1e999`, `1e-999`, `9007199254740993`, or `1.5` in an integer position is none of those. §16.1's 'wrong-typed required member' rule is about JSON types (string/number/boolean/...), and such a literal IS a JSON number. An implementer must therefore invent one of at least three readings: (a) reject with -32602/1201, (b) accept and clamp/round, (c) accept and propagate the platform value. The reference implementation demonstrates the divergence inside a single package: `CompanionEngine.surfaceRevision` (CompanionEngine.kt:553-559) rejects out-of-range integers; `validateReminder`'s at_ms (CompanionEngine.kt:924-927) rejects fractional and out-of-range values with an explicit comment about parser boxing; `validateAction`'s ttl_s (SpecValidator.kt:900-906) tests `d.isInfinite()`; but `validatePositiveInt` (SpecValidator.kt:589-594), `date_stamp.year` (518-522), canvas dims (709-714) and the slider bounds (447-457) all accept Infinity. Two conformant-by-their-own-reading endpoints will disagree on the same frame.

**Failure scenario:** A receiver gets `{"t":"date_stamp","day":1,"month_index":1,"year":1e999}`. Reading (a) answers 1201 content-invalid; reading (c) — which the current SpecValidator implements — accepts and renders a year derived from Infinity. Nothing in the document lets an implementer or a conformance suite decide which is correct, and the golden corpus cannot encode an expectation for the case.

**Proposed fix:** Add a receiver paragraph to §4.2, e.g.: 'A receiver MUST reject a message in which a member declared as an EBP integer carries a JSON number that is not mathematically integral or lies outside the inclusive safe-integer range, and MUST reject a member declared as `number` whose literal does not convert to a finite binary64 value. The rejection uses the error the containing method defines for an invalid parameter (-32602) or invalid content (1201); it MUST NOT be silently clamped, truncated, or rounded.' Add a matching row to contract.json's field-type table so validate.py can assert it, and add golden fixtures for `1e999`, `1e-999`, `9007199254740993`, and `1.5`-in-an-integer-slot.

## [P2] [unverified] §4.2 / §7.5 vs §7.2 — §4.2 and §7.5 still declare request IDs string-only, contradicting §7.2 as amended by #34 — and §18.1's rpc.cancel path depends on it

**SPEC line:** 142  
**Auditor:** Audit SS18.1 through SS18.3 (dialogs incl. the dialog.show request and

**SPEC quote:**
> EBP request IDs are strings; Section 7.2 prohibits numeric request IDs.

**Detail:** Amendment #34 (SPEC-CHANGES.md:1) rewrote §7.2 to read "A request ID MUST be either a JSON string or a JSON integer... A host JSON-RPC library that allocates sequential integer IDs per connection — such as core Emacs `jsonrpc.el` — therefore conforms without adaptation" (SPEC.md:487-494), specifically so ebp.el could rent core jsonrpc.el unmodified. The amendment lists its touched sections as "§7.2, §6.2, §24.2" and two other normative sentences were left stale: (1) SPEC.md:142 in §4.2 still asserts "EBP request IDs are strings; Section 7.2 prohibits numeric request IDs" — a direct contradiction of the section it cites; (2) SPEC.md:535 in §7.5 still requires rpc.cancel params to be "`{id}` where `id` is the exact string request ID being cancelled". This is not cosmetic for §18.1: rpc.cancel is one of the three enumerated ways an outstanding dialog concludes ("the caller sends `rpc.cancel`, which concludes it with error `1301`", SPEC.md:2217), and the reference Emacs endpoint's dialog.show requests carry jsonrpc.el's integer IDs. A literal reading of §7.5 makes every dialog the reference endpoint opens uncancellable — or, read the other way, makes an integer `id` in rpc.cancel "malformed" and therefore something the receiver "MUST be logged and ignored". The implementation reads it the permissive way (CompanionEngine.kt:707-714 matches `dialogs.entries.find { it.value == cancelId }` on whatever JSON type arrived), which is almost certainly the intent but is not what the text says. §2.2 artifact precedence gives no tiebreak between two SPEC sentences.

**Failure scenario:** Emacs (core jsonrpc.el) sends dialog.show with id 7 and later wants to abandon it, sending {"method":"rpc.cancel","params":{"id":7}}. Under §7.5's literal text this is a malformed cancellation that the Companion MUST log and ignore, leaving the dialog modal on the device forever; under §7.2 it is well-formed and MUST conclude the request with 1301. Two conforming Companions written from the same document behave oppositely on the reference endpoint's only cancellation path.

**Proposed fix:** Amend §4.2: delete the sentence at line 142 or replace it with "Request IDs follow Section 7.2; integer request IDs are safe integers under this section." Amend §7.5 line 535 to "Its params MUST be `{id}` where `id` is the exact request ID being cancelled, of the same JSON type and value as the original request's `id` under Section 7.2." Add a SPEC-CHANGES row noting these as follow-on corrections to amendment #34, and extend the frames.golden integer-id vector with an rpc.cancel carrying an integer id.

## [P2] [unverified] §4.5 / §20.1 — §20.1's "canonical size under Section 4.5" for the device report is undefined — §4.5 defines canonical (JCS) sizing only for max_field_bytes and max_input_state_bytes, leaving the welcome reservation's device term unbound to the wire encoding

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1643  
**SPEC line:** None  
**Auditor:** Audit SS4.5 (limits and bounds) exhaustively. Enumerate EVERY limit na

**SPEC quote:**
> The `limits` object uses these members. All byte counts refer to UTF-8 or stored payload octets as applicable, not characters. For `max_field_bytes` and `max_input_state_bytes`, encoded size means the UTF-8 length of the logical value serialized by the JSON Canonicalization Scheme [RFC8785]. … When serializing a value governed by either limit, the Companion MUST use a representation no longer than that value's JCS representation, so optional escaping or whitespace cannot defeat the budget.  …  (§4.5) This reservation covers surface histories, profiles, limits, and the complete device report, counted at `max_device_report_bytes`, before any surface is admitted.  …  (§20.1) The complete device report's canonical size under Section 4.5 MUST NOT exceed `limits.max_device_report_bytes`.

**Detail:** Amendment #40 added max_device_report_bytes and made §20.1 measure the report by its "canonical size under Section 4.5". But §4.5's sizing paragraph (SPEC.md:214-221) defines "encoded size" as the JCS UTF-8 length for exactly two members — max_field_bytes and max_input_state_bytes — and the follow-on MUST that a serialized representation be "no longer than that value's JCS representation" is explicitly scoped to "either limit". No rule ties max_device_report_bytes to any particular serialization. Two readings are permitted: (a) the JCS UTF-8 length of the report object, or (b) the exact UTF-8 length of the `device` member as this Companion actually emits it. They can differ substantially, because nothing forbids the welcome serializer from emitting a longer-than-canonical form (\uXXXX escaping of non-ASCII, or whitespace). Since §4.5 counts the reservation term "at max_device_report_bytes", reading (a) makes the always-fits-max_frame_bytes guarantee unprovable at the wire — precisely the hole amendment #40 set out to close. The reference implementation picks a third thing: checkLimits measures config.deviceReport.toString() (org.json, CompanionEngine.kt:1643), which is neither JCS (member order is insertion order, not code-point order) nor guaranteed identical to the emitted copy built at CompanionEngine.kt:1561.

**Failure scenario:** A Companion advertising `capabilities` reports launchable_packages containing non-ASCII app labels. Its report measures exactly max_device_report_bytes = 8192 under reading (a) (JCS emits raw UTF-8: a 4-octet emoji costs 4 octets), so §20.1 is satisfied. Its welcome serializer escapes non-ASCII, so the emitted `device` member is ~24 KB. checkLimits' inequality (CompanionEngine.kt:1647) reserved only 8192, so B + 8192 + max_input_state_bytes - 2 <= max_frame_bytes held at startup while the real welcome is ~16 KB over its proven budget. With max_input_state_bytes and worst-case surfaces near the cap, the emitted welcome exceeds max_frame_bytes and encodeFrame refuses it — the same class of failure the W7 audit already recorded for the omitted device term.

**Proposed fix:** Amend §4.5's limit-encoding paragraph to name max_device_report_bytes alongside max_field_bytes and max_input_state_bytes: state that its encoded size is the JCS UTF-8 length of the complete device report, and extend the existing "the Companion MUST use a representation no longer than that value's JCS representation" obligation to cover the emitted `device` member. Alternatively, define max_device_report_bytes directly as the UTF-8 octet length of the `device` member exactly as serialized in the welcome, and delete "canonical" from §20.1. Either way, add a sentence to the reservation paragraph making explicit that the device term counted at max_device_report_bytes is the wire length of the emitted member.

## [P2] [unverified] §6.2 — SPEC never defines the header-line grammar, so `malformed header line` is unresolvable — the three reference artifacts already disagree

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/FrameCodec.kt`:105  
**SPEC line:** 402  
**Auditor:** Audit SS5 (transport profiles) and SS6 (Content-Length framing) agains

**SPEC quote:**
> A receiver MAY ignore an unknown syntactically valid ASCII header field. It MUST close the transport connection when the header section:

- lacks `Content-Length`;
- contains more than one `Content-Length`;
- exceeds 8,192 octets;
- contains a malformed header line; or
- declares a body larger than 4,194,304 octets.

**Detail:** §6.1 fixes the syntax of the one header a sender emits, but §6.2 defines neither "syntactically valid ASCII header field" nor "malformed header line" for any *other* field — no field-name charset, no rule on an empty field name, no rule on bare CR/LF inside a value, and no receiver rule on leading zeroes. The three normative-adjacent artifacts in this repo already diverge on the same bytes: (a) `X Y: 9\r\nContent-Length: 2\r\n\r\n{}` — FrameCodec.kt:105 rejects (`name.any { it.code > 0x7E || it.code < 0x21 }` → FrameClose), while ebp.el:202 performs no name validation at all and validate.py:338-346 only checks ASCII-decodability, so both accept-and-ignore; verified empirically on ebp.el, which decodes the frame. (b) `: 9\r\nContent-Length: 2\r\n\r\n{}` (empty field name) — all three accept-and-ignore, though an empty field name is not a syntactically valid field. (c) `Content-Length: 007` — §6.1's no-leading-zeroes rule is a *sender* MUST and §6.2's receiver reject-list (signed/fractional/empty/non-decimal/overflowing) does not mention it; "007" is unambiguously decimal, yet all three close. A third-party receiver that accepted 7 would be equally defensible and no golden pins it. An implementer must invent the grammar, and interoperability between two independently written conformant receivers is not guaranteed.

**Failure scenario:** Two conformant EBP 2 receivers written from the SPEC alone disagree on `X-Trace Id: abc\r\nContent-Length: 2\r\n\r\n{}`: one closes the connection citing "malformed header line", the other ignores the unknown field and decodes the frame. Both read the same normative text. The same split occurs on `Content-Length: 007` (close vs. accept as 7), and neither case has a golden to arbitrate under §2.2 artifact precedence.

**Proposed fix:** Amend §6.2 with an explicit ABNF for the header line and a definition of malformed: `header-line = field-name ":" *WSP field-value *WSP`, `field-name = 1*tchar` with `tchar = %x21-39 / %x3B-7E` (visible ASCII excluding `:`), `field-value = *(%x20-7E / HTAB)`; a line that does not match — including an empty field name, a name containing SP/HTAB/CTL/non-ASCII, a value containing any octet outside that set (notably bare CR or LF), or a line with no colon — is a malformed header line and MUST close. Add one sentence pinning the receiver's leading-zero disposition (recommend: a `Content-Length` value with a leading zero MUST be rejected, matching all three reference decoders), and add two wire goldens (`X Y: 9…` and `Content-Length: 007`, both `expect_error: close`) so the grammar is machine-checked.

## [P2] [unverified] §7.2 / §7.3 (with §7.1, §6.2) — SPEC never defines the response owed to a request whose `id` violates §7.2's grammar; the reference Companion's intended -32600 is dead code and it answers nothing

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:371  
**SPEC line:** 474  
**Auditor:** Audit SS7 (JSON-RPC 2.0 conventions) and SS8 (error model) in both twi

**SPEC quote:**
> Every EBP request MUST receive exactly one response unless the connection dies
first.

**Detail:** §7.2 prohibits `null`, fractional, empty, over-64-octet, and non-identifier request IDs, but §7.3's taxonomy enumerates responses only for unknown methods, wrong endpoint/class, and structurally invalid params — never for a request whose id itself violates the grammar. §6.2 mandates `id: null` responses only for the top-level-array / non-object / invalid-JSON cases, which do not cover a well-formed message object carrying a bad id. Three readings are all defensible: (a) drop silently, on the theory that a message with a prohibited id is not an "EBP request" so §7.1's exactly-one-response duty never attaches; (b) answer `-32600` echoing the offending id, per §7.3's wrong-shape bullet; (c) answer `-32600` with `id: null`, per JSON-RPC 2.0's rule that an undetectable id is Null. The reference Companion contains readings (a) and (b) in direct conflict: `handleRequest` opens with `if (!isValidRequestId(id)) return respondError(id, -32600, "Invalid Request", "invalid-request")` (CompanionEngine.kt:370-371), but `respondError` is itself guarded by `if (isValidRequestId(id))` (CompanionEngine.kt:1658-1665, comment: "a request id is never null"), so that branch emits nothing — unreachable-by-construction dead code whose observable behavior is silent drop. `emitFramingError` (CompanionEngine.kt:1669-1674) exists precisely to bypass that guard for `id: null` but is wired only to the §6.2 body-level catches in `feed` (CompanionEngine.kt:109-118), never to this path. The gap is reachable: `classifyMessage` (Envelope.kt:26-38) uses `msg.has("id")`, which is true for `"id": null` because org.json stores JSONObject.NULL, so an id-null request classifies as REQUEST and then vanishes.

**Failure scenario:** The peer sends `{"jsonrpc":"2.0","id":null,"method":"queue.replay","params":{}}` (or the same with `"id":1.5`, `"id":""`, or a 65-character id, all of which `isValidRequestId` rejects). The Companion emits nothing on the wire and stays open; the sender's request never concludes and hangs until its local timeout, and during §10.3's barrier the synchronization stalls. A different conformant implementation answers -32600 echoing the id, and a third answers -32600 with `id: null` — three incompatible observable behaviors for one frame, none of which the SPEC prefers.

**Proposed fix:** Amend §7.2 with a receiver clause: "A receiver that receives a request whose `id` violates this section MUST answer `-32600 Invalid Request` with `id: null` and MAY continue the connection, exactly as Section 6.2 specifies for an unaddressable message." Add the vector to §24.6 item 4. In the impl, route CompanionEngine.kt:370-371 through `emitFramingError(-32600, "Invalid Request", "invalid-request")` so the guard at line 1661 no longer silently swallows it, and add a CompanionEngineTest case feeding `id: null`, `id: 1.5`, `id: ""`, and a 65-char id.

## [P2] [unverified] §7.5 — §7.5 still requires `rpc.cancel` to carry "the exact string request ID", so an integer-id request cannot be cancelled

**SPEC line:** 535  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 1 thr

**SPEC quote:**
> Its params MUST be `{id}` where `id` is the exact string request ID being
cancelled. A malformed cancellation notification MUST be logged and ignored.

**Detail:** Amendment #34 made integer request IDs legal in §7.2 specifically so core `jsonrpc.el` — which allocates sequential integers per connection — conforms without adaptation, but §7.5 was not amended. Read literally, `{"id": 7}` is not "the exact string request ID", so it is a malformed cancellation notification and the receiver "MUST be logged and ignored"; read charitably, "string" is stale wording and any §7.2-legal ID is meant. The SPEC also never says how the receiver disambiguates the ID: §7.2 scopes uniqueness to "that sender's outstanding requests on the connection", so after #34 both directions can legitimately have an outstanding request with id 7 at the same time, and §7.5's only disambiguator is the sender-side phrase "for an outstanding request it originated" — no receiver-side rule states that the lookup is confined to requests received from that peer.

**Failure scenario:** Emacs (renting jsonrpc.el, integer ids) shows a dialog with `dialog.show` id 7, the user backgrounds the app, and Emacs sends {"jsonrpc":"2.0","method":"rpc.cancel","params":{"id":7}}. Companion A follows §7.5 literally, treats the notification as malformed, ignores it, and the dialog stays outstanding until the transport dies — §18.1 line 2217's documented cancellation path ("the caller sends `rpc.cancel`, which concludes it with error `1301`") is unreachable for every jsonrpc.el-based Emacs. Companion B (the reference, CompanionEngine.kt:707-713, which compares `params.opt("id")` by equality) cancels the dialog and answers 1301. Worse, a Companion that resolves the id against its own outbound requests can match its own outstanding `event.action` id 7 and cancel a durable delivery Emacs never asked to cancel.

**Proposed fix:** Amend §7.5: "Its params MUST be `{id}` where `id` is the exact request ID being cancelled — a string or integer per Section 7.2, compared under Section 4.3 equality including its JSON type. The receiver MUST resolve `id` only among the requests it has received from that peer and has not yet answered; it MUST NOT match its own outstanding outbound request IDs, whose ID space is independent under Section 7.2."

## [P2] [unverified] §7.5 (vs §7.2) — §7.5 still requires `rpc.cancel` to name "the exact string request ID", contradicting §7.2's integer IDs after amendment #34

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:709  
**SPEC line:** 535  
**Auditor:** Audit SS7 (JSON-RPC 2.0 conventions) and SS8 (error model) in both twi

**SPEC quote:**
> Its params MUST be `{id}` where `id` is the exact string request ID being
cancelled.

**Detail:** Amendment #34 rewrote §7.2 to read "A request ID MUST be either a JSON string or a JSON integer... A host JSON-RPC library that allocates sequential integer IDs per connection — such as core Emacs `jsonrpc.el` — therefore conforms without adaptation" (SPEC.md:487-494), and SPEC-CHANGES lists the touched sections as "§7.2, §6.2, §24.2". §7.5 was not swept and still says the cancellation id is "the exact string request ID" (SPEC.md:535-536). The two sections now contradict for exactly the configuration the amendment blessed: the Emacs endpoint rents jsonrpc.el, whose request ids are always integers, and the only long-lived cancellable Emacs-originated request in the protocol is `dialog.show` (§18.1 — held open with no protocol timeout; ebp.el:1245-1261 uses a 3600 s client-side ceiling). Under a literal §7.5 reading no Emacs-originated request is cancellable at all; under §7.2's reading `{"id": 7}` is well-formed; a third reading — stringify the integer, `{"id": "7"}` — is what "exact string request ID" most naturally invites and is silently wrong. The reference Companion picks the §7.2 reading: `handleNotification`'s `rpc.cancel` branch (CompanionEngine.kt:707-714) compares the raw JSON value `params.opt("id")` against the stored `dialog.show` request id with `==`/equals, so an Integer matches an Integer while a stringified "7" matches nothing and is silently dropped under "Cancellation of an unknown ID MUST be ignored" (SPEC.md:539-540).

**Failure scenario:** Emacs (jsonrpc.el ids) sends `dialog.show` with id 12, the user aborts, and Emacs follows §7.5 literally by sending `{"jsonrpc":"2.0","method":"rpc.cancel","params":{"id":"12"}}` (a string, as §7.5 demands). CompanionEngine.kt:709 finds no dialog whose stored id equals the String "12" (the stored id is the Integer 12), returns, and the dialog stays outstanding on screen; the request never concludes with the `1301 request-cancelled` §7.5 mandates, and Emacs waits until its 3600 s `ebp-dialog-timeout`.

**Proposed fix:** Amend §7.5 to drop "string": "Its params MUST be `{id}` where `id` is the request ID being cancelled, carrying the exact JSON type and value of the original request's `id` (§7.2). An `id` whose JSON type or value does not equal an outstanding originated request ID MUST be ignored." File it as amendment #63, noting it is a corrigendum to #34, which changed §7.2 without sweeping its dependents. No contract or golden change is needed — contract.json's `rpc.cancel` params carry no type constraint pinning string.

## [P2] [unverified] §9.1 — §9.1's failed-proof rate-limit rule is unimplementable as written and vacuously satisfiable on android-loopback-tcp

**SPEC line:** 620  
**Auditor:** Audit SS9 (pairing and mutual authentication) against companion/wire/A

**SPEC quote:**
> The Companion MUST rate-limit failed proofs per pairing ID and source process or connection.

**Detail:** Three gaps make this MUST unenforceable and untestable. (1) No quantity: no rate, no window, no lockout duration, no threshold — a Companion that inserts a 1 ms delay and one that fences the identity for an hour both claim conformance, and no §24.6 vector can check either. (2) "source process" is not obtainable under the only defined profile: an accepted loopback TCP socket carries no peer credentials on Android/Linux (SO_PEERCRED is AF_UNIX-only; /proc scraping by local port is racy and blocked by hidden-API/SELinux policy on modern Android). An implementer must either invent an out-of-scope mechanism or silently drop that half of the conjunction. (3) The "or connection" alternative is self-defeating against §9.3's "followed by connection close": a connection can host at most one failed proof, so per-connection limiting is always trivially satisfied while unlimited reconnects give unbounded attempts — exactly what the reference implementation does today. §23.6 explicitly places the local process inside the threat model ("Loopback addressing … does not authenticate a local process. The HMAC handshake supplies that authentication"), so this is the one control standing between a hostile local app and online guessing.

**Failure scenario:** Two implementers read the same sentence and ship incompatible security postures, and neither can be failed by a conformance suite. Implementer A counts failures per connection: since §9.3 forces a close after the single failed proof each connection can carry, A's counter never reaches any threshold, so A performs no limiting at all while claiming the MUST is met — this is literally the reference implementation's posture (CompanionEngine.handleAuth, no ledger). Implementer B keys on pairing ID with a persistent lockout. A hostile local app therefore gets unbounded guesses against A and 5 against B, with no §24.6 item able to distinguish conformance from non-conformance because no rate, window, or key is specified.

**Proposed fix:** Amend §9.1 to: (a) require the limiter's state to be keyed by pairing ID and to survive connection close and Companion process restart, explicitly stating that per-connection counting alone does not satisfy the requirement; (b) name a concrete floor, e.g. "after 5 failed proofs for a pairing ID the Companion MUST refuse further `auth.response` for that ID with `1203` for at least 60 seconds, doubling to a cap of 1 hour, reset only by a successful authentication or by user action"; (c) drop "source process" from the normative conjunction and demote it to a SHOULD conditioned on the transport profile exposing peer credentials, with a note that `android-loopback-tcp` does not; and (d) add a §24.6 adversarial item requiring a suite to prove the backoff survives reconnects.

## [P2] [unverified] §9.2 — §9.2 never defines the response to a well-formed but unknown `pairing_id`, putting §9.1's non-disclosure rule at risk

**SPEC line:** 650  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 1 thr

**SPEC quote:**
> capability names make the params invalid. A protocol mismatch MUST receive
`1202 protocol-version`; another invalid hello field MUST receive `-32602`.

**Detail:** The §9.2 params table constrains `pairing_id` only as "32 lowercase hex characters ... Selects the pairing identity" (line 645). A syntactically perfect pairing ID that names no stored pairing is neither a protocol mismatch nor an "invalid hello field" by type, so §9.2 gives no outcome, and §10.1's state table only says CONNECTED accepts `session.hello`. §9.1 constrains the outcome indirectly — "It MUST NOT reveal whether an unknown pairing ID or an incorrect proof caused authentication failure" (lines 621-622) — but that sentence is scoped to "authentication failure", and an implementer may reasonably classify a hello-time rejection as a params failure that precedes authentication. Two readings: (a) unknown identity is an invalid field value -> `-32602` (or `1203`) at hello, no challenge issued; (b) always issue a fresh `server_nonce`, then fail at `auth.response` with `1203` and close. The SPEC also never requires the unknown-identity path to be timing-indistinguishable: §9.3's constant-time rule covers only "well-formed proofs", not the token lookup, so a Companion may skip HMAC entirely for an unknown ID.

**Failure scenario:** The user re-pairs on the phone (§9.1: "Re-pairing creates a new pairing ID and an empty state partition"), while the Emacs endpoint still holds the old pairing ID. Companion A answers the hello with -32602 invalid-params; Emacs's error handling classes -32602 as a local encoding bug, logs it, and retries the identical hello in a reconnect loop forever, never telling the user to re-pair. Companion B (the reference, CompanionEngine.kt:1496-1501) issues a nonce and answers auth.response with 1203 auth-failed, which Emacs surfaces as "re-pair required". Separately, on Companion A an unprivileged local process enumerates which pairing IDs exist by observing -32602 versus a `server_nonce`, defeating §9.1's non-disclosure requirement.

**Proposed fix:** Amend §9.2: "A `pairing_id` that satisfies its grammar but names no stored pairing MUST NOT be distinguished at this step. The Companion MUST create a fresh server nonce, return it, and enter `CHALLENGED` exactly as for a known identity, then fail the subsequent `auth.response` with `1203 auth-failed` and close. The work performed and the latency observable to the peer for an unknown identity SHOULD be indistinguishable from a known identity with an incorrect proof (for example, by verifying against a per-boot dummy key)." Cross-reference §9.1.

## [P3] [unverified] SS14.4 — SS14.4/SS15.3 define the disposition of a malformed event.action result only for durable replay, leaving a live `drop` event's bad result undefined

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:332  
**SPEC line:** 1397  
**Auditor:** Audit SS14.4 through SS14.6 (the event.action request protocol, EventI

**SPEC quote:**
> Emacs MUST validate the action allowlist, arguments, surface context, revision, and durable ID before invoking application behavior. It MUST return exactly one of:

**Detail:** SS15.3 supplies the only enforcement sentence — 'A result with an unknown status or invalid result shape is a protocol violation: the Companion MUST retain the event, send at most one safe `log.error`, and close the connection' — but that clause sits inside the numbered replay algorithm and speaks of retaining the event, which a live `drop` event does not have. SS14.4 states the four-status obligation on Emacs without saying what a Companion does when it is broken outside replay. The implementation splits accordingly: onPumpResult treats an unknown status as fatal (CompanionEngine.kt:524-534, log.error + close), while the live drop path at CompanionEngine.kt:332-334 does `callback?.invoke(result?.optString("status"), error)` — an absent or garbage status becomes "" or the raw string, DeviceBridge ignores anything that is not an error (DeviceBridge.kt:150-158), and the session continues as if nothing happened. A result of `{}` for a live drop event is thus silently indistinguishable from success.

**Failure scenario:** A buggy or hostile Emacs answers a live drop event.action with {"result":{}} or {"result":{"status":"maybe"}}. Companion A (this code) treats it as a benign non-error and shows nothing; Companion B, applying SS15.3's rule uniformly, sends log.error and tears the connection down. Both cite the same spec, and Emacs cannot predict whether a malformed result costs it the session.

**Proposed fix:** Hoist the protocol-violation rule out of SS15.3 into SS14.4, scoped to every event.action result: 'A result whose `status` is absent or is not one of `accepted`, `duplicate`, `stale`, or `rejected`, or whose shape is otherwise invalid, is a protocol violation. For a durable event the Companion MUST retain the record; for a live `drop` event it MUST show a local diagnostic. In both cases it MUST send at most one safe `log.error` and close the connection.' Leave SS15.3 to reference it.

## [P3] [unverified] §10.1 — §10.1 leaves the connection state after a rejected handshake request undefined, and never defines "failed handshake"

**SPEC line:** 755  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 1 thr

**SPEC quote:**
> transition directly from any state to `CLOSED`. A failed handshake MUST NOT be
retried on the same connection.

**Detail:** The surrounding sentence makes closure optional — "Authentication failure, timeout, framing failure, transport loss, explicit replacement by a newer authenticated session, and local shutdown MAY transition directly from any state to `CLOSED`" — and §9.3 mandates a close only for `auth.response` failures ("MUST receive `-32602` followed by connection close"; "a well-formed but reused, mismatched, or incorrect proof or nonce MUST receive `1203` followed by connection close"). For a rejected `session.hello` (§9.2's `1202` or `-32602`), no section says whether the Companion closes or stays in `CONNECTED`, and "failed handshake" is never defined: it may mean only an authentication failure, or any error response to a handshake method. The receiver-side consequence is unspecified in both readings — §10.1's own rule ("In `CONNECTED`, a structurally valid request other than `session.hello` MUST receive `1200 not-authenticated`") means a second `session.hello` is not "other than `session.hello`", so a retried hello must apparently be processed, contradicting the sender-side MUST NOT with no receiver duty attached.

**Failure scenario:** Emacs sends a hello with 129 entries in `wants` and receives -32602. Emacs corrects the list and re-sends `session.hello` on the same connection. Companion A (the reference, CompanionEngine.kt:1494, which responds and leaves the state at CONNECTED) processes the retry and the session proceeds — a state the SPEC says MUST NOT happen. Companion B treated the -32602 as a failed handshake and closed, so Emacs's retry is written into a dead socket and the user sees a connection failure instead of a working session. Because the SPEC forbids the retry but obliges neither endpoint to close, no Emacs implementation can know whether the connection remains usable after a handshake error.

**Proposed fix:** Amend §10.1: "A failed handshake is any error response to `session.hello` or `auth.response`, including `1202`, `-32602`, and `1203`. The receiver MUST close the connection immediately after emitting a handshake error response, and the sender MUST dial a new connection rather than retry on the closed one." Then §9.2's `1202`/`-32602` and §9.3's closes read uniformly, and §5.3's wake/reconnect path is unaffected.

## [P3] [unverified] §10.2 — §10.2 does not say whether a surface profile MUST be omitted when its capability was not granted

**SPEC line:** 844  
**Auditor:** Audit SS10 (session lifecycle and negotiation) — states, the welcome m

**SPEC quote:**
> `surface_profiles` maps presentation targets to positive-knowledge profiles. `app` is REQUIRED. `notification`, `widget`, `tile`, and `dialog` are REQUIRED only when the corresponding surface capability was granted. Each profile MUST contain distinct `node_types`, `builtins`, and `features` arrays and MUST list exactly what the Companion will honor on that target during this session.

**Detail:** The two sentences pull in opposite directions and the section never resolves them. "REQUIRED only when ... granted" states a floor and is silent on whether emitting an ungranted target's profile is permitted; "MUST list exactly what the Companion will honor on that target during this session" implies an ungranted target's profile must be empty or absent, since the Companion will honor nothing there (surface.update on an ungranted namespace is 1201 namespace-not-granted, dialog.show is -32601). §10.4 supplies a reason to lean the other way — "its absence does not by itself erase a previously accepted persistent surface" and "Emacs MAY always send a revisioned `surface.remove` for a surface reported in the welcome, even when it did not request that surface's presentation capability" — so a Companion may reasonably report a notification profile beside a retained `notification:*` history in `surfaces`. Two conforming implementations therefore emit different welcomes for identical `wants`, and §10.2's own instruction to Emacs ("MUST gate every emitted node, builtin, and constraining feature against the target profile and MUST NOT interpret a missing profile or list as support for everything") gives Emacs no rule for the opposite case: a present profile for an ungranted target. The reference emits the full static three-profile object regardless of grants (CompanionEngine.kt:1546 over NodeSupport.surfaceProfiles(), NodeSupport.kt:76-82), so with wants=[] Emacs is handed a `dialog` profile containing dialog.submit/dialog.dismiss for a session in which dialog.show is answered -32601.

**Failure scenario:** Emacs sends wants=["theme"]. Companion A omits `dialog` and `notification`; Companion B (the reference) includes both, fully populated. Emacs gates emission against the profiles as §10.2 commands: against A it correctly never attempts a dialog; against B it authors and sends dialog.show, receives -32601, and must fall back at runtime — the profile it was told is authoritative for "what the Companion will honor during this session" was wrong. A conformance suite asserting either welcome shape rejects the other.

**Proposed fix:** Amend §10.2 to state the rule explicitly. Recommended: "A Companion MUST omit a `notification`, `widget`, `tile`, or `dialog` profile whose surface capability was not granted, and MUST omit from any emitted profile every builtin whose own capability was not granted (for example `trigger.fire` without `triggers`). Emacs MUST treat an absent profile as no support for that target, and MUST still send a revisioned `surface.remove` for a reported surface in that namespace under Section 10.4 without consulting a profile." If instead reporting ungranted profiles is intended to be legal, say so and define what Emacs may conclude from one.

## [P3] [unverified] §10.3 — §10.3 defines no Companion behavior for `session.ready` that arrives before or during a `queue.replay`

**SPEC line:** 871  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 1 thr

**SPEC quote:**
> 4. call `queue.replay` and wait for it to conclude; and
5. call `session.ready`.

**Detail:** Steps 4 and 5 are stated as an Emacs obligation ("After verifying the welcome, Emacs MUST perform these steps in order"), but no receiver-side rule enforces or reacts to a violation, and §10.3 gives `session.ready` no failure mode at all — "`session.ready` params and result are both `{}`" — while simultaneously implying it can fail: "The Companion MUST enter `READY` only after `session.ready` succeeds." §15.3 defines `1600 queue-busy` only for a concurrent `queue.replay`, and §8 has no code meaning "the synchronization barrier was not observed". Readings: (a) `session.ready` always succeeds and the Companion answers immediately even with a replay in flight; (b) the Companion defers the `{}` response until the active replay concludes; (c) the Companion rejects with `1204 session-state` or `1600 queue-busy`. Reading (a) has an ordering consequence the SPEC never addresses: §10.3 requires the READY-entry `state.changed` flush to precede "newly generated events", but says nothing about the replayed `event.action` already outstanding, and §14.6 requires divergent values to be flushed "before sending an `event.action` whose handler could observe those values".

**Failure scenario:** Emacs calls `queue.replay`, and (through a timeout or a concurrency bug) sends `session.ready` while the first replayed `event.action` is still outstanding. Companion A answers `{}`, enters READY, and flushes SYNCING-era `state.changed` values that now arrive AFTER an event.action whose Emacs handler already ran against the pre-flush state. Companion B holds the `{}` response until the replay concludes, so Emacs blocks in SYNCING until the backlog drains. Companion C answers 1204 session-state, for which Emacs has no defined recovery — no rule permits re-sending `session.ready`, so the session is wedged in SYNCING until the transport is torn down.

**Proposed fix:** Amend §10.3: "`session.ready` is legal with or without a preceding `queue.replay`, and never fails for barrier reasons. When a replay is active, the Companion MUST NOT serialize the successful `{}` response until that replay has concluded; it MUST NOT reject `session.ready` with `1204` or `1600`. The Section 10.3 flush and the release of newly generated events both follow that response."

## [P3] [unverified] §12 — §12's protocol-mismatch rule is one-directional and its boundary with -32602 is undefined: the welcome's `protocol` has no verification duty, and a missing or non-integer hello `protocol` is answered 1202

**Location:** `emacs/ebp.el`:641  
**SPEC line:** 959  
**Auditor:** Audit SS11 (method registry) and SS12 (versioning and compatibility). 

**SPEC quote:**
> `protocol` is the EBP wire major. This document defines major `2`. A Companion
MUST reject another major with `1202 protocol-version` and SHOULD include
`data.supported: [2]`. A sender MUST NOT infer wire compatibility from an
implementation version, document version, or `contract.json` format version.

**Detail:** Two undefined edges in the same rule.

(1) The welcome direction has no rule. §10.2 (SPEC.md:806, 816) makes `protocol` a REQUIRED welcome member with normative shape "integer `2`", but §12 states a MUST only for the Companion rejecting Emacs's hello. Nothing says what Emacs does when the welcome's `protocol` is not 2. ebp.el implements exactly the letter: `ebp--welcome-required` (emacs/ebp.el:640-643) lists `:protocol` and `ebp-client--on-welcome` (:650) tests only `plist-member` — presence, never value. A welcome carrying `protocol: 3` is absorbed at :662 and the session proceeds to SYNCING speaking major 2. The §9.3 proof binds the major only through the literal `"EBP/2 companion:"` prefix (SPEC.md:674), so this is caught incidentally by a Companion that also changed its proof string, and not at all by one that did not — an implementer cannot tell whether the §12 check is required, redundant, or forbidden.

(2) The 1202-vs--32602 boundary is undefined. §9.2 (SPEC.md:650-651) says "A protocol mismatch MUST receive `1202 protocol-version`; another invalid hello field MUST receive `-32602`" while its own params table (SPEC.md:643) declares `protocol` an integer that MUST equal 2. Whether `protocol: "2"`, `protocol: 2.5`, `protocol: null`, or an ABSENT `protocol` is "a protocol mismatch" or "another invalid hello field" is unresolved. `handleHello` (CompanionEngine.kt:1471-1476) tests `params.opt("protocol") != 2` and so answers 1202 with `data.supported:[2]` for all four, including the absent case, where `opt` returns null. An implementer reading the table as a type constraint would answer -32602 for all four.

**Failure scenario:** (1) A Companion whose welcome builder regresses and emits `protocol: 3` (or an on-path implementation that intends major 3 but reuses the EBP/2 proof strings) completes the handshake with this Emacs endpoint: `ebp-client--on-welcome` (emacs/ebp.el:645-707) verifies the server proof, absorbs `granted`/`surfaces`/`limits`, steps to `syncing`, and immediately issues `surface.update`/`queue.replay`/`session.ready` in major-2 encoding against an endpoint that just declared a different wire major. §12's entire purpose — that the major is the compatibility signal — is unenforced in this direction.
(2) Emacs sends `session.hello` with `protocol` omitted (a plain missing-required-member bug). CompanionEngine.kt:1472 answers `1202 protocol-version` with `data.supported:[2]`. Emacs's §12 handling reads that as "no compatible major exists" and stops retrying/downgrades, when the correct diagnosis is a malformed request that -32602 would have named. A second Companion that treats the type table as governing answers -32602 for the same bytes; both are conforming.

**Proposed fix:** Amend §12 to make the rule bidirectional and to fix the boundary: "A `protocol` member that is absent or is not a JSON integer is an invalid field and MUST receive `-32602`; a `protocol` member that is an integer other than `2` is a version mismatch and MUST receive `1202 protocol-version` with `data.supported: [2]`. Emacs MUST verify that the welcome's `protocol` equals `2` before absorbing any other welcome member and MUST close the connection when it does not." Then: in CompanionEngine.handleHello, split the check into `protocol !is Int -> -32602` and `protocol != 2 -> 1202`; in ebp.el, add `(equal (plist-get result :protocol) 2)` to the `ebp-client--on-welcome` cond (emacs/ebp.el:649-653) with a `'(protocol-mismatch)` close reason alongside the existing `welcome-incomplete` branch.

## [P3] [REFUTED] §14.1 — §14.1 does not define capture_fields scope inside a multi-view surface — cross-view capture and the value of a never-presented view are both undefined

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:121  
**SPEC line:** 1241  
**Auditor:** Audit SS14.1 through SS14.3 (ActionDescriptor shape, the dotted action

**SPEC quote:**
> `capture_fields` is valid only for a descriptor inside a surface or dialog
containing every named stateful node. Its length MUST NOT exceed
`max_capture_fields`. Each name MUST resolve to exactly one
stateful node in that document.

**Detail:** §13.4 makes a multi-view `app:*` SurfaceSpec a `{views, initial_view}` object, and §14.6 scopes stateful-ID uniqueness to "one surface snapshot", so the whole multi-view object is one document. §14.1 then says resolution happens "in that document", which permits a descriptor in view `a` to name a stateful node that exists only in view `b`. But only one view is presented at a time (§13.4; the reference renders exactly one via DeviceBridge.resolveView, DeviceBridge.kt:228-233), so §14.1's other MUST — "copy all selected current values" — has no defined answer for a node the user has never seen. Two readings: (A) document-wide resolution, capturing the authored default of the unpresented node; (B) resolution scoped to the view containing the descriptor, so a cross-view name is "absent" and the document MUST be rejected. The reference takes (A): SpecValidator.validateSurfaceSpec builds one `Ctx` and walks every view into the same `ctx.statefuls` map (SpecValidator.kt:97-111) before resolving `captureRefs` against it at 121-125, and SurfaceStore.currentValue falls back to `authoredValue(node)` for a node with no draft (SurfaceStore.kt:107-110). Neither reading is excluded by the text, and §14.1's own occurrence-time rule ("Any remote action whose meaning depends on a stateful node's current value MUST name that node in capture_fields") is the guarantee that reading (A) quietly weakens.

**Failure scenario:** A multi-view surface has view `form` containing `{t:"text_input", id:"note", value:"draft"}` and view `list` containing `{t:"button", label:"Send", on_tap:{action:"note.send", when_offline:"drop", capture_fields:["note"]}}`. The user is on `list` and has never opened `form`. Companion A (the reference) accepts the surface and sends `fields:{note:"draft"}` — the authored default of a field the user never saw, presented as an occurrence-time user value. Companion B rejects the surface with `1201 content-invalid` at the capture_fields path. Emacs cannot tell which behavior to expect and, under A, receives a "captured" value that no user ever confirmed.

**Proposed fix:** Amend §14.1's capture_fields paragraph to pin multi-view scope. Recommended text: "In a multi-view surface (Section 13.4), a descriptor's `capture_fields` MUST resolve within the view that contains the descriptor; a name that resolves only in another view is absent and the Companion MUST reject the containing document. Stateful IDs remain unique across the whole snapshot." If the looser rule is preferred instead, state it and add the missing value rule: "a captured stateful node in a view that has never been presented captures its authored value under Section 17.4's defaults." Add a `frames.golden`/validator fixture for a cross-view capture so the chosen rule is executable.

**Verdicts:**
- `CODE TRUTH` refuted=True (high): The code behaves as described (SpecValidator.kt:97-125 builds one Ctx, walks every view into one `ctx.statefuls`, then resolves captureRefs document-wide; CompanionEngine.kt:271-278 captures via `surfaces.currentValue(surface, fieldId)` with no view dimension) — but the SPEC reading the finding calls ambiguous is pinned by three lines it does not reconcile. (1) §14.1 sentence 1 names the scope uni
- `SPEC TEXT` refuted=True (high): The quote at SPEC.md:1241-1245 is verbatim and normative, but the claimed gap is already closed elsewhere and reading (B) is textually excluded.

1. "that document" is a defined term and it is the whole multi-view object. SPEC.md:1666-1667 (§16.1): "Every authored node `id` MUST be unique across the complete surface or dialog document, including input-stateful, collapsible, tabs, and editor nodes.
- `MATERIALITY` refuted=True (high): Both premises fail against the spec's own text, and the residual consequence is nil.

(1) The scope is not ambiguous. SPEC.md:1666 (§16.1) defines the word the finding calls underspecified: "Every authored node `id` MUST be unique across the complete surface or dialog document" — "document" is the complete surface, and §13.4 (SPEC.md:1103-1117) makes `views` a member of that one SurfaceSpec, not a

## [P3] [REFUTED] §14.2 — §14.2 does not say whether `trigger.fire`'s "registered manual trigger" requirement is an accept-time document-validity condition or a tap-time condition

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:228  
**SPEC line:** 1300  
**Auditor:** Audit SS14.1 through SS14.3 (ActionDescriptor shape, the dotted action

**SPEC quote:**
> `clipboard.copy`, `share.send`, and `trigger.fire` are OPTIONAL and MUST be
positively advertised in each profile where they are usable; `trigger.fire`
additionally requires the `triggers` capability and a registered `manual`
trigger.

**Detail:** The preceding paragraph ends "An unexpected parameter or invalid context MUST reject the containing document" (SPEC.md:1294-1295), which pushes builtin context validity into surface.update validation. But the trigger registry is a separate, independently mutable resource: `triggers.set` is a full replace-set (§21.1) that can be sent before or after any surface.update, and a registration can disappear while a surface is cached. Two readings follow. (A) Accept-time: a `surface.update` whose spec names `{builtin:"trigger.fire", id:"coffee"}` MUST be rejected with 1201 when no `manual` trigger `coffee` is currently registered — which makes surface acceptance order-dependent on triggers.set and means a later `triggers.set` that drops `coffee` retroactively invalidates an already-accepted, still-displayed surface with no defined remedy. (B) Tap-time: the document is accepted and the builtin is inert until a matching manual trigger exists. The reference takes (B): validateAction performs no trigger lookup, and executeBuiltin gates at tap with `if ("triggers" !in granted) return` and `firing.fireManual(...)` (CompanionEngine.kt:228-234), which no-ops for an unregistered id. The capability half has the same problem: `granted` is fixed for a session, but a cached surface can outlive the session that authored it (§13.5), so "requires the triggers capability" is also not obviously an accept-time predicate.

**Failure scenario:** Emacs sends `surface.update` for `app:home` containing a `{builtin:"trigger.fire", id:"coffee"}` button, then sends `triggers.set` registering the manual trigger `coffee`. Companion A (reading A) answers the surface.update with `1201 content-invalid reason="unknown-trigger"`; Companion B (reading B, the reference) answers `{status:"applied"}` and the button works after the triggers.set lands. Emacs cannot author a portable ordering, and there is no defined behavior for a later triggers.set that removes `coffee` while `app:home` is still the accepted snapshot.

**Proposed fix:** Amend §14.2 to separate the two conditions. Recommended text: "Advertisement in the applicable target profile is an accept-time condition: a `trigger.fire` descriptor in a target whose profile does not advertise it MUST reject the containing document. The `triggers` capability grant and the existence of a registered `manual` trigger with the named `id` are occurrence-time conditions: the Companion MUST accept the document and MUST treat activation as a clean no-op, with a local diagnostic, when the capability is not granted or no such `manual` trigger is registered at that moment. A subsequent `triggers.set` that removes the named trigger MUST NOT invalidate an already-accepted surface." Mirror the same accept-time/occurrence-time split in §21.5's `manual` row.

**Verdicts:**
- `CODE TRUTH` refuted=True (high): The finding's code claims all reproduce (SpecValidator.validateAction, SpecValidator.kt:878-955, does no trigger lookup; CompanionEngine.kt:228-234 gates at tap with `if ("triggers" !in granted) return` then `firing.fireManual`, which no-ops via `store.registration(identity, triggerId) ?: return` in TriggerRuntime.kt:157-159) — but reading (A) is not actually available in the SPEC, so there is no 
- `MATERIALITY` refuted=True (high): Reading (A) is not an available reading, so the two-Companion divergence the finding needs is unreachable. Three spec lines close it. (1) SPEC.md:2923 (§21.1) — "Removed IDs MUST NOT fire." The finding's load-bearing claim, "there is no defined behavior for a later triggers.set that removes `coffee` while `app:home` is still the accepted snapshot," is textually false: the spec states the deregistr
- `SPEC TEXT` refuted=True (high): Quote is verbatim (SPEC.md:1299-1302), but the claimed fork is already closed by other SPEC text, so the "gap" is imaginary. (1) Reading (A) is not textually available. §14.2 states a CLOSED enumeration of accept-time rejection conditions for builtins — SPEC.md:1271-1273 ("both variants, neither variant, a remote-only member on a builtin, an unknown builtin, or invalid builtin parameters") and SPE

## [P3] [unverified] §14.4 — §14.4's stated validation order contradicts its own duplicate-suppression MUST for a replayed event whose action is no longer allowlisted

**Location:** `emacs/ebp.el`:898  
**SPEC line:** None  
**Auditor:** Audit emacs/ebp.el as a whole against every SPEC duty assigned to "a c

**SPEC quote:**
> Emacs MUST validate the action allowlist, arguments, surface context, revision,
and durable ID before invoking application behavior.

**Detail:** §14.4 SPEC line 1399-1400 fixes an order in which the allowlist check precedes the durable-ID check. SPEC line 1433-1435 then states: "Emacs MUST retain a durable record of accepted event IDs for at least 604800 seconds. On a repeated ID, it MUST return `duplicate` and MUST NOT deliberately repeat the application effect." For a redelivered event whose `event_id` is already in the receipt store but whose `action` is no longer registered, the two MUSTs give different answers and the document never resolves precedence. The dispositions differ observably: per §14.4's status table, `rejected` makes the Companion "Delete durable record and surface a diagnostic" while `duplicate` makes it "Delete durable record" silently — so the stated order produces a user-visible rejection diagnostic for an event Emacs in fact accepted. The reference implementation checks duplicate first (emacs/ebp.el:898-903) while its own docstring claims the SPEC order ("Validation order per 14.4: envelope, allowlist, duplicate ID", emacs/ebp.el:887), so the code, its documentation, and the SPEC are three-way inconsistent.

**Failure scenario:** Emacs accepts event `E` for action `heading.todo-set` and commits its receipt. The connection drops before the Companion records the permanent result, so `E` stays queued. Emacs restarts; the user has since removed the org module that called `ebp-client-register-action` for `heading.todo-set`. On reconnect, replay redelivers `E`. Following SPEC line 1399, Emacs returns `rejected` and the Companion shows the user "action permanently invalid" for work that was already done. Following SPEC line 1434 (and the reference impl), Emacs returns `duplicate` and the record is deleted silently. Both are conforming under one MUST and non-conforming under the other.

**Proposed fix:** Amend §14.4 to make the durable-ID check unconditionally first, since a receipt is proof the event was already fully validated once: replace "Emacs MUST validate the action allowlist, arguments, surface context, revision, and durable ID before invoking application behavior." with "Emacs MUST check the durable event ID first and return `duplicate` for a repeated ID without further validation. Otherwise it MUST validate the action allowlist, arguments, surface context, and revision before invoking application behavior." Then correct the `ebp-client--handle-event-action` docstring (emacs/ebp.el:886-888) to describe the order the code actually implements.

## [P3] [unverified] §14.4 (with §15.1, §22.3) — §14.4's `queued_at_ms` "queued delivery only" is undecidable once §15.1/§22.3 require pre-delivery persistence for every `queue`/`wake` event

**SPEC line:** 1378  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 14 th

**SPEC quote:**
> | `queued_at_ms` | timestamp | queued delivery only | Time first persisted for offline/retry delivery |

**Detail:** §14.4's table conditions `queued_at_ms` on "queued delivery only". But §15.1:1563-1564 ("For `queue` or `wake`, persistence MUST precede every wake or delivery attempt, including when a `READY` session already exists") and §22.3:3332-3334 ("the Companion MUST durably admit the event before its first `event.action` attempt even when a `READY` session is currently available") mean EVERY `queue`/`wake` event is persisted before its first attempt. "Queued delivery" therefore has two readings: (A) any event delivered from the durable queue — which is every `queue`/`wake` event, so `queued_at_ms` is always present for them; or (B) delivery that actually waited, i.e. a replay or a post-reconnect attempt, so a `queue` event delivered immediately while `READY` omits it. The SPEC never defines the term, and unlike `fields` (§14.4:1380, "MUST be omitted when empty. It MUST NOT be sent as `null`") there is no explicit prohibition on the other side. §15.1:1554-1556 requires the persisted record to include both "creation time, queue time" without saying whether the queue time reaches the wire on a first-attempt delivery.

**Failure scenario:** An Emacs handler distinguishes live from replayed intent with `(if (plist-get params :queued_at_ms) 'replayed 'live)` — replayed events skip the "done!" toast because the user acted minutes ago. Companion A (reading A) stamps `queued_at_ms` on every `queue` event including one tapped while online, so the confirmation toast never appears. Companion B (reading B) omits it and the toast appears. Worse, an Emacs endpoint that validates the envelope strictly under §7.3 and treats `queued_at_ms`-on-a-live-event as invalid params returns `-32602`, which by §15.3:1616 pins the queue head permanently (see the §15.3 finding above).

**Proposed fix:** Replace the "queued delivery only" cell in §14.4's table with an unambiguous rule and add a defining sentence after the table: "`queued_at_ms` MUST be present on every `event.action` whose descriptor policy is `queue` or `wake`, and MUST be absent on every `drop` event. It records the instant the durable record was first committed (§15.1), and MUST NOT change across retries of the same `event_id`. Presence of `queued_at_ms` indicates durable admission, not that the event waited for a session; an endpoint MUST NOT use it to infer that delivery was delayed." If instead the delayed-delivery signal is wanted, define a separate boolean or derive it from `occurred_at_ms` vs receipt time and say so.

## [P3] [unverified] §15.4 — §15.4's "conservatively" gives no floor for implementation storage overhead, so max_queued_bytes is unverifiable and the reference counts zero overhead

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/DurableQueue.kt`:135  
**SPEC line:** 1648  
**Auditor:** Audit SS15 (durable queue and replay) against DurableQueue.kt, QueueSt

**SPEC quote:**
> The aggregate byte check MUST count stored payload,
metadata, captured fields, and implementation storage overhead conservatively.

**Detail:** "conservatively" names a direction but no quantity, no unit, and no measurable predicate, so no conformance suite can test it and two implementations can differ by orders of magnitude while both claiming conformance. The permitted readings run from "count the exact on-disk footprint of the store (framing, indices, journal, filesystem block rounding)" to "count nothing beyond the record bytes", which is what the reference does: `DurableQueue.admit` computes `prospectiveBytes = kept.sumOf { it.toString().toByteArray(UTF_8).size } + record.toString().toByteArray(UTF_8).size` (DurableQueue.kt:135-136), i.e. the sum of the records' own serializations. The actual `FileQueueStore` document adds the `{"records":[…],"next_seq":N,"clock_high_water":M}` envelope and the inter-element commas (QueueStore.kt:53-56) — roughly 60 + (n−1) bytes — which are never counted, so the stored artifact can exceed `max_queued_bytes`. The absolute size is trivial here, but the rule as written cannot distinguish this from an implementation that stores each record in a 4 KiB-padded slot and also counts only the JSON.

**Failure scenario:** A conformance suite sets `max_queued_bytes` to exactly the serialized size of 256 maximal records and admits them one by one. Implementation X (the reference) admits all 256 and writes a file ~315 bytes larger than the advertised cap. Implementation Y counts a 512-byte-per-record overhead allowance and refuses at record 200 with `1601 queue-full`. Both cite §15.4 line 1648; the suite cannot declare either non-conformant, and Emacs cannot predict from the advertised limit how many events it may actually queue.

**Proposed fix:** Amend §15.4 to pin the check to a measurable quantity: "The Companion MUST compute the aggregate as the total octets its storage format would occupy for the prospective record set, including per-record framing and any container envelope, and MUST NOT under-count. An implementation MAY substitute a fixed per-record overhead constant provided it is greater than or equal to its true per-record framing cost and is reported in `limits` (or documented in the conformance report)." Correspondingly, `DurableQueue.admit` should add the envelope and separator bytes (or a stated per-record constant) to `prospectiveBytes`.

## [P3] [unverified] §16.2 — §16.2's "treated EXACTLY as an unknown type" does not say whether §16.1's `id` identifier-format and document-uniqueness rules still apply to an unknown or unadvertised node — the reference validator applies them and rejects the whole surface

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:392  
**SPEC line:** None  
**Auditor:** Audit SS16 (UI document model) — SS16.1 node identity and the identity

**SPEC quote:**
> A node type the Companion implements but that is absent from the applicable
target's advertised `node_types` MUST be treated EXACTLY as an unknown type:
its subtree is scanned for nested valid nodes, but its per-type schema is not
applied, it registers no stateful draft, and it dispatches nothing. The strict
per-member validation of Section 16.1 applies only to advertised and Core Node
Set types.

**Detail:** §16.2 says the strict per-member validation of §16.1 applies only to advertised and Core Node Set types, but §16.1 also carries a document-wide invariant — "Every authored node `id` MUST be unique across the complete surface or dialog document" — and the `id` member is universal (§16.5), not per-type. Neither reading is excluded: (a) `id` is a §16.1 per-member rule, so an unknown node's `id` is neither format-checked nor uniqueness-checked; (b) `id` uniqueness is a document invariant that survives the degrade. `SpecValidator.validateNode` picks (b): it runs the IDENTIFIER regex, the MAX_IDENTIFIER_OCTETS check and `ctx.ids.add(id)` at lines 392-398, *before* the degrade early-return at line 402 — so a version-skewed sender's unknown node can 1201 the entire update, which is the opposite of the "defensive behavior for a nonconforming or version-skewed sender" §16.2 is written to provide. The two readings are wire-observable and cannot both be right.

**Failure scenario:** A newer Emacs sends to an older Companion `{"t":"column","children":[{"t":"timeline","id":"row 7","children":[{"t":"text","text":"fallback"}]}]}`, where `timeline` is a post-2.0 node type and its `id` uses a space (legal in the future revision that introduced it, illegal under today's §4.4 identifier grammar). Reading (a): the Companion degrades the unknown node, renders the nested `text`, and the user sees "fallback". Reading (b) — this implementation: `SpecValidator.kt:395` throws `invalid identifier` and the whole `surface.update` is rejected with 1201, so the surface never appears at all and the defensive fallback §16.2 mandates is never exercised. The same split occurs for two unknown nodes that happen to share an `id`.

**Proposed fix:** Amend §16.2 to name the exact members that survive the degrade, e.g.: "For a node treated as unknown, a Companion MUST NOT apply any per-member rule of Section 16.1 or Section 17 other than the requirement that `t` be a string; in particular it MUST NOT reject the update because such a node's `id` or `key` is not a valid identifier, and MUST NOT count that `id` toward the document-wide uniqueness requirement of Section 16.1 (which is scoped to advertised and Core Node Set nodes)." If instead the uniqueness invariant is meant to be document-wide, say so explicitly and state that the identifier *format* rule is still not applied. Add a §24.6 item 13 vector for an unknown node carrying an ill-formed and a duplicate `id`.

## [P3] [unverified] §16.6 — §16.6 defines a fallback only for an unknown *role*, leaving a malformed Color (bad hex length, non-hex digits, non-string) unresolved, and never restricts "hex digits" to ASCII

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/ColorModel.kt`:15  
**SPEC line:** None  
**Auditor:** Audit SS16 (UI document model) — SS16.1 node identity and the identity

**SPEC quote:**
> A Color is either a theme-role identifier or one of `#rgb`, `#rgba`,
`#rrggbb`, or `#rrggbbaa`. Hex digits are case-insensitive. Theme-role names are
resolved from the active theme. A Companion receiving an unknown role MUST use
a legible platform fallback and MUST NOT make content transparent.

**Detail:** A value such as `"#12345"`, `"#zz0"`, `"#"`, `""` or a JSON number is neither one of the four hex forms nor a theme-role identifier (§4.4 identifiers must start `[A-Za-z0-9]`, so a leading `#` disqualifies them). §16.6's only MUST is scoped to "an unknown role", so nothing in the SPEC says whether a malformed Color rejects the surface with 1201 or falls back. Implementations will diverge: the reference implementation funnels everything unparseable into the *role* `when` and lands on `else -> scheme.onSurface` (ColorModel.kt:82), i.e. it treats `"#12345"` as an unknown role, and `Attributes.kt:149` reaches it via `node.optString("bg")`, whose org.json coercion turns `{"bg":42}` into the string "42" and then into a dark background — while a validator-first implementation would 1201 the whole update. Second gap in the same sentence: "Hex digits are case-insensitive" does not say ASCII-only. `parseHexColor` (ColorModel.kt:18) gates on `Char.isDigit()` and parses with `digitToInt(16)` / `String.toLong(16)`, all of which accept any Unicode Nd digit, so `"#٣٣٣"` (U+0663 ×3) and `"#３３３"` (fullwidth) parse as #333 — a conformance suite cannot say whether that is required, permitted, or forbidden.

**Failure scenario:** Emacs (or a buggy app layer) emits `{"t":"box","bg":"#12345","children":[{"t":"text","text":"Balance"}]}`. Companion A rejects the surface with `1201 content-invalid` (malformed Color) and the user sees nothing; Companion B (this implementation) paints the box with `onSurface` — a near-black fill in the light scheme — under the `text` node's own `onSurface` label, producing unreadable content that no rule forbids because the fallback clause only speaks about roles. A third Companion could reasonably treat the value as "absent" and paint nothing.

**Proposed fix:** Amend §16.6 to close both holes: "Hex digits are the ASCII characters `0-9`, `a-f`, `A-F`; a `#`-prefixed value with any other character or with a length other than 3, 4, 6, or 8 hex digits is a malformed Color. A Companion MUST treat a malformed Color, and a Color member whose JSON type is not a string, exactly as an unknown role: it MUST apply a legible platform fallback appropriate to the member's use (foreground vs. background) and MUST NOT reject the update, MUST NOT make content transparent, and MUST NOT paint a foreground and its background with the same fallback color." Also state whether a theme-role identifier is a legal *value* inside a §18.4 `colors` map (today Color is defined recursively; `ThemeModel.role()` accepts hex only), and project the hex grammar into `contract.json` as a `field_types.color` pattern.

## [P3] [unverified] §17.5 — §17.5 never says whether canvas ops are clipped to the declared `width`/`height`, permitting a canvas to paint over unrelated chrome

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/VisualizationNodes.kt`:195  
**SPEC line:** 2079  
**Auditor:** Audit SS17.4 through SS17.6 (layout nodes, the scaffold and its slots,

**SPEC quote:**
> Coordinates are finite numbers in the canvas coordinate space. A Companion MUST skip an unknown canvas operation, MUST NOT treat it as executable code, and MUST continue rendering known operations. Canvas has no implicit interaction or animation. … Canvas `width` and `height` MUST be positive.

**Detail:** §17.5 requires positive `width`/`height` and calls the ops' coordinates "the canvas coordinate space", but never states the relationship between the two: whether the declared box is a CLIPPING viewport (ops outside it are not drawn), whether it is merely a layout request that ops may overflow, or whether the coordinate space is SCALED to whatever size the node is finally laid out at (the §16.5 universal `width`/`max_width`/`fill_fraction`/`aspect_ratio` can all give the node a size other than the declared one). §16.5's `clip` attribute is defined as "Clip descendants to the corner shape" and defaults to `false`, and canvas ops are not descendants — so an author cannot even opt in to clipping. This is a separate gap from the already-known dp-vs-px unit question: it is about bounds and scale, not units. The reference impl chooses no-clip + no-scale: `Canvas(modifier = m.size(wDp.dp, hDp.dp))` (VisualizationNodes.kt:195) draws through `drawBehind`, which does not clip to the node's bounds, and `px()` (196) maps op coordinates 1:1 regardless of the node's measured size.

**Failure scenario:** Emacs authors `{"t":"canvas","width":60,"height":60,"ops":[{"op":"rect","x":-400,"y":-800,"width":2000,"height":2000,"fill":"#cc0000"}]}` as a 60×60 badge whose op is deliberately oversized to bleed to the badge's edges. On this Companion the rect paints a full-screen red wash over the scaffold's top bar, body, and buttons; on a clipping Companion it is a 60×60 red square. Under the scaling reading, a canvas placed with `fill_fraction: 1` would additionally draw at a completely different scale on a tablet than on a phone.

**Proposed fix:** Amend §17.5 with an explicit bounds rule, e.g.: "The declared `width` and `height` define both the node's requested layout size and its clipping viewport: the origin is the top-left of the node's content box, `+x` runs toward the inline end and `+y` downward, and a Companion MUST clip drawing to that box. Op coordinates are NOT rescaled when the node is laid out at a different size; content outside the declared box is not drawn. `chart` has the same clipping duty." Then apply `Modifier.clipToBounds()` in RenderCanvas.

## [P3] [unverified] §17.7 — §17.7 never says whether long_press is a full ToolbarItem, so the reference rejects a spec-legal long_press that omits label/icon

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:824  
**SPEC line:** 2127  
**Auditor:** Audit SS17.7 (editor toolbar: snippets, substitution tokens, placement

**SPEC quote:**
> A ToolbarItem MUST contain `label` or `icon` and exactly one operation … It MAY contain `placement` (`cursor`, `line-start`, or `block`) and `long_press`, which contains exactly one non-menu operation. A Companion MUST reject an item with zero or multiple primary operations.

**Detail:** §17.7 describes `long_press` only by its operation count; it never states that long_press is itself a ToolbarItem, and contract.json's `toolbar` block ({ops, line_ops, placements, snippet_placeholders}) defines no long_press shape, so the label-or-icon MUST is unresolved for it. The reference routes long_press through the same validateToolbarItem (SpecValidator.kt:866) whose first check is `if (!item.has("label") && !item.has("icon")) throw ContentInvalid(path, "ToolbarItem needs label or icon")` (line 824). Yet the renderer never displays a long_press label or icon — ToolbarItem draws the PARENT's icon/label and only invokes runOp(longPress) on long click (EditorToolbar.kt:139-151) — so the required member is provably decorative. widgets.golden contains no long_press fixture and SpecValidatorCompletenessTest.kt:174-176 only tests a long_press that has a label, so neither reading is pinned.

**Failure scenario:** Emacs pushes {icon:"format_bold",snippet:"**${selection}**",long_press:{snippet:"__${selection}__"}} — a bold chip whose long press inserts underline. Under the natural reading of line 2138 this is legal (exactly one non-menu operation). The reference rejects the WHOLE surface.update with 1201 content-invalid at path …toolbar[0].long_press ('ToolbarItem needs label or icon'), and the author has no way to discover that an invisible label is demanded.

**Proposed fix:** Amend §17.7 to say explicitly which ToolbarItem rules apply to `long_press`: it is a ToolbarItem-shaped object that MUST carry exactly one non-menu primary operation, MAY carry `placement`, MUST NOT carry `menu` or a nested `long_press`, and — since it is never rendered as its own chip — `label`/`icon` are OPTIONAL on it (or, if a title is wanted for an accessibility announcement, say so and keep them REQUIRED). Then align SpecValidator.validateToolbarItem with an `requireAffordance` flag and add both golden/unit cases.

## [P3] [unverified] §18.1 — §18.1 names dialog styles `sheet`/`sheet_full` but states no presentation obligation and provides no advertisement channel for them

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1397  
**SPEC line:** 2201  
**Auditor:** Audit SS18.1 through SS18.3 (dialogs incl. the dialog.show request and

**SPEC quote:**
> `style` is OPTIONAL and is `dialog` (default), `sheet`, or `sheet_full`. An unrecognized `style` value MUST fall back to `dialog` (Section 12 rule 6); a Companion MUST NOT reject a dialog for an unknown `style` alone.

**Detail:** Amendment #41 (SPEC-CHANGES.md:8) closed the UNKNOWN-value hole but left the RECOGNIZED-value obligation undefined. §18.1 never says what `sheet` or `sheet_full` mean presentationally, never says a Companion MUST present them differently from `dialog`, and — unlike node types, builtins, and features — provides no `surface_profiles.dialog` slot in which a Companion could advertise which styles it supports. §24.3 (SPEC.md:3458-3462) makes the omission load-bearing: an implementation "MAY advertise a subset of an entry-by-entry catalog... only where the containing module expressly permits subsets", and §18.1 expressly permits no such subset. So an implementer must invent one of two incompatible policies: (i) all three styles are REQUIRED presentation modes of the surfaces.dialog module, or (ii) `style` is an advisory hint a Companion MAY ignore wholesale. This implementation takes (ii) implicitly — handleDialogShow (CompanionEngine.kt:1397-1428) never reads `style`, never forwards it to dialogListener, and MainActivity always presents a centered androidx Dialog (MainActivity.kt:86-97) — which happens to satisfy amendment #41 for unknown values only because it ignores the member entirely. Emacs has no way to discover which it is dealing with, so a sender cannot know whether authoring `style:"sheet_full"` for a long form will produce a full-height sheet or a cramped centered box.

**Failure scenario:** Emacs authors a long multi-field capture form as dialog.show {dialog_id:"capture", style:"sheet_full", spec:{...20 inputs...}} on the reasonable belief that `sheet_full` gets a full-height presentation. On this Companion it renders as a centered modal Dialog whose content overflows the screen with no scroll affordance, and Emacs receives no signal that the requested style was ignored — there is no error, no advertisement to consult, and no fallback report.

**Proposed fix:** Amend §18.1 to state the obligation explicitly, e.g.: "A Companion granted `surfaces.dialog` MUST implement all three `style` values as distinct presentations (`dialog` centered-modal, `sheet` partial-height bottom sheet, `sheet_full` full-height sheet), each modal and each preserving the Section 18.1 completion contract; a Companion that cannot MUST present `dialog` and MUST NOT advertise `surfaces.dialog`." Alternatively, if subsetting is intended, add a `styles` array to `surface_profiles.dialog`, require it when `surfaces.dialog` is granted, require `dialog` to be present in it, and require an unadvertised style to fall back to `dialog` exactly as an unrecognized one does.

## [P3] [unverified] §18.2 — §18.2 never defines what a Companion does with an out-of-domain duration_s, so the toast is either shown or silently destroyed

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1374  
**SPEC line:** 2253  
**Auditor:** Audit SS18.1 through SS18.3 (dialogs incl. the dialog.show request and

**SPEC quote:**
> `toast.show` params are `{text, duration_s?}`. `text` is REQUIRED and MUST be plain text. `duration_s` MUST be `1..10`; omission selects a platform default.

**Detail:** The `1..10` bound is stated as a sender obligation with no receiver disposition. §12 rule 6 (SPEC.md:978-979) covers only "Unknown enum values", so an out-of-range NUMBER on a known member has no governing rule, and §16.3's unknown-field rule does not apply to a known field with a bad value. Three readings are all defensible: (a) drop the whole notification as structurally invalid params under §7.3 (SPEC.md:514); (b) ignore the invalid optional member and use the platform default, the treatment §12 rule 1 gives an unusable optional member; (c) clamp into 1..10. The reference implementation picks (a) — handleToastShow (CompanionEngine.kt:1374-1379) returns without presenting anything when the value is outside 1..10 or is not an Int/Long — and ToastTest.kt:81-86 pins that choice as if it were normative. Reading (b) is at least as reasonable and is strictly friendlier for a "best-effort presentation". The same paragraph also leaves `text` with no length bound at all (a 4 MB toast body is legal under §4.5 since only max_frame_bytes applies), and leaves the JSON type of `duration_s` unstated — §4.2 line 152 says durations named `*_s` are integer seconds, but the reference rejects `5.0`, which §4.3 declares equal to `5`.

**Failure scenario:** Emacs sends {"method":"toast.show","params":{"text":"Saved 42 notes","duration_s":15}} — a sender bug in the duration only. Companion A (reading (a), this implementation) shows nothing at all; the user never learns the save happened. Companion B (reading (b)) shows "Saved 42 notes" for its platform default. Both claim §18.2 conformance. Likewise `duration_s: 5.0` is presented by a §4.3-equality reader and dropped by this one.

**Proposed fix:** Amend §18.2 to pin the disposition, e.g.: "`duration_s` MUST be an integer 1..10. A Companion receiving a `duration_s` outside that range or of another type MUST ignore the member and present the toast at its platform default rather than suppress the toast; `text` remains REQUIRED and a toast without a valid `text` MUST be dropped. `text` MUST NOT exceed 4096 UTF-8 octets; a longer value MAY be truncated for display." Project the bound into contract.json as a typed range on toast.show.duration_s.

## [P3] [unverified] §18.3 — Pie-menu `items` arrays have no upper bound while `categories` is bounded 1..10

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:776  
**SPEC line:** 2260  
**Auditor:** Audit SS18.1 through SS18.3 (dialogs incl. the dialog.show request and

**SPEC quote:**
> `categories` MUST be an array of one through ten objects containing `label: string`, optional `icon: identifier`, and exactly one of `items` or `on_tap: remote ActionDescriptor`. `items` is a non-empty array of objects containing `label: string`, a remote ActionDescriptor named `on_tap`, and optional `icon: identifier`.

**Detail:** The outer ring is explicitly capped at ten, which is the constraint a radial presentation actually needs; the nested ring gets only "non-empty". §4.5 defines no `max_pie_items` (and `max_pie_menus` counts menus, not entries — SPEC.md:300), so the only bound on a nested ring is max_frame_bytes. Two divergent readings follow: (a) `items` inherits the same 1..10 intent as `categories` and a Companion MUST reject an eleventh item, or (b) `items` is genuinely unbounded and the Companion must present whatever arrives. The implementation takes (b): validPieCategories checks `items.length() < 1` only (CompanionEngine.kt:776-777), and the presenter lays every entry around one fixed 320 dp ring at `2*PI*k/n` (PieMenu.kt:41-53), so entries overlap into illegibility well before any protocol limit is reached. Because a pie menu is dropped-not-answered when invalid, a sender gets no feedback either way. The same paragraph also leaves nesting depth implicit — the grammar happens to permit exactly one level because an item has no `items` member, but §18.3 never states "nesting is exactly one level deep", so an implementer reading the item object as extensible under §12 rule 1 could accept and try to present deeper trees.

**Failure scenario:** Emacs authors a capture menu with one category whose `items` array holds 60 org capture templates. Companion A (reading (a)) drops the whole pie_menu.show and shows nothing; Companion B (this one, reading (b)) accepts it and draws 60 buttons at 6-degree spacing on a 320 dp ring, mutually overlapping so that no wedge can be reliably tapped — and since selection injects `item_index`, a mis-tap fires the wrong allowlisted action.

**Proposed fix:** Amend §18.3 to bound the nested ring and pin the depth, e.g.: "`items` MUST be an array of one through ten objects... Pie menus nest exactly one level: an `items` entry MUST NOT itself contain `items`. A menu violating either rule is invalid and MUST be dropped under the rule below." Project the bound into contract.json beside the existing categories bound, and add a negative golden for an eleven-item nested ring.

## [P3] [unverified] §18.4 — §18.4's SyntaxStyle advisory escape is conditioned on a predicate the implementer alone decides ("cannot express them per role"), making the PRESENT-overrides-intrinsic precedence rule unenforceable

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/SyntaxHighlight.kt`:78  
**SPEC line:** 2316  
**Auditor:** Audit SS18.4 (theme.set, color roles, dark tri-state/follow-system fro

**SPEC quote:**
> A SyntaxStyle's PRESENT members override the Companion's own intrinsic per-role styling, each independently, and ABSENT members fall back to the Companion default; a Companion MAY honor only `fg` and treat `bg`, `font_weight`, `italic`, and `underline` as advisory where its highlighter cannot express them per role.

**Detail:** Amendment #58's stated intent is "Clarifying prose matching the reference (fg-honored, others advisory)", but the normative sentence it produced does not grant an unconditional MAY — it grants one only "where its highlighter cannot express them per role". Nothing defines "cannot express". Under the objective reading (the rendering toolkit is capable of per-role weight/style), the reference is NON-conformant: `syntaxFg` (SyntaxHighlight.kt:78-86) reads only `fg`, while the tokenizer emits per-role `fontStyle = FontStyle.Italic` for comments (SyntaxHighlight.kt:185, :301, :387) and `fontWeight = FontWeight.Bold` for keywords (:219, :329) — Compose `SpanStyle` plainly can express all five members per role, so the escape's condition is false and the MUST-override applies. Under the subjective reading (the implementation's own per-role style table has no slot for them, which is true of `SyntaxColors` at :27-40), the escape applies. Because the predicate is a property the implementer controls by construction, ANY Companion can satisfy it by declining to build the table, which makes the preceding "PRESENT members override" precedence rule vacuous — the exact ambiguity amendment #58 was written to remove. There is also no wire mechanism (a `features` entry, a device-report field) by which Emacs can discover which members a given Companion honors, so an author cannot compensate.

**Failure scenario:** Emacs pushes `theme.set {"syntax":{"comment":{"fg":"#616E88","italic":false},"keyword":{"fg":"#81A1C1","font_weight":"normal"}}}` to mirror a theme whose comments are upright and whose keywords are not bold. The reference recolours both roles but still draws comments italic (SyntaxHighlight.kt:185) and keywords bold (:219), because `syntaxFg` discards every non-`fg` member. Two implementers reading the same sentence ship visibly different fontification for the identical `theme.set`, and neither can be shown non-conformant.

**Proposed fix:** Replace the trailing clause with an objective rule. Either (a) drop the condition and make it unconditional — "a Companion MAY honor only `fg` and MUST treat `bg`, `font_weight`, `italic`, and `underline` as advisory" — which matches the reference and amendment #58's stated intent; or (b) keep the MUST-override and require a Companion that honors only `fg` to advertise that fact (e.g. a `syntax.fg-only` entry in the applicable profile's `features`) so Emacs can author around it. Option (a) is the smaller change and should also add a sentence forbidding a Companion from applying intrinsic per-role styling that contradicts an ignored advisory member where doing so is avoidable.

## [P3] [unverified] §18.4 (vs §9.1) — §18.4's theme-persistence MUST is not scoped to the pairing identity, though §9.1 requires revocation to erase "themes" for one identity

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/DeviceBridge.kt`:93  
**SPEC line:** 2296  
**Auditor:** Audit SS18.4 (theme.set, color roles, dark tri-state/follow-system fro

**SPEC quote:**
> Every field is optional. The Companion MUST merge missing roles with a legible platform fallback, MUST persist the latest accepted theme, and MUST treat each notification as a complete replacement of the previously pushed values.

**Detail:** §9.1 (SPEC.md:607-612) requires revocation to "erase its token, queued payloads, input drafts, cached surfaces, tombstones, themes, reminders, triggers, and identity-scoped shortcuts", and states the pairing ID "selects the correct token and persistent state partition" — which presupposes that a persisted theme belongs to an identity partition. §18.4 never says so. Every other durable artifact got an explicit scoping sentence: reminders by amendment #49 ("the durable store MUST be partitioned by pairing identity", SPEC.md:2411), the queue "per-pairing" in §15.1, shortcuts "identity-scoped" in §20.3. Themes were left out. The two readings diverge observably: (a) one device-global theme, so pairing B's `theme.set` replaces pairing A's persisted mirror and revoking B must decide whether to wipe A's appearance; (b) one theme per identity, restored when that identity authenticates. The reference takes reading (a) — `DeviceBridge.kt:93` opens a single `File(appContext.filesDir, "ebp-theme.json")` with no pairing component, written unconditionally in `themeListener` (DeviceBridge.kt:306-310) and re-delivered to the UI at process start before any authentication (DeviceBridge.kt:109). §18.4 also never says what the persistence is FOR — whether the persisted theme MUST be applied to §13 cached surfaces rendered while no session exists — so an implementer may legally persist the bytes and still render restored surfaces in the native scheme until Emacs re-pushes.

**Failure scenario:** Two pairings are configured on one device (the config at DeviceBridge.kt:53-56 holds a `pairings` map, so this is structural, not hypothetical). Pairing A pushes a dark Nord mirror; pairing B later connects and pushes `theme.set {"colors":null}`. `ebp-theme.json` is overwritten, A's persisted mirror is gone, and A's cached surfaces render in the native scheme on the next cold start with no session — while a §9.1 revocation of B would have to erase the file that now also represents A. Under reading (b) neither would have happened.

**Proposed fix:** Amend §18.4 in the paragraph at line 2296 with the amendment-#49 pattern: "The persisted theme is scoped to the pairing identity; the durable store MUST be partitioned by identity so that revocation under Section 9.1 erases exactly that identity's theme, and one pairing's `theme.set` MUST NOT alter another's persisted mirror." Add a second sentence pinning the purpose: "The persisted theme MUST be applied whenever the Companion renders that identity's cached surfaces, including before and between sessions." Reference impl follow-up: key the theme file by pairing ID (`ebp-theme-<pid>.json`) and select it after authentication.

## [P3] [unverified] §18.5 (with §13.5, §13.1) — §18.5/§13.5 never define what a platform-level notification dismissal does to the surface's persisted snapshot, so a dismissed notification may resurrect

**SPEC line:** 2358  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 14 th

**SPEC quote:**
> `dismiss: true` dismisses the
notification only after the action occurrence is safely admitted under its
offline policy.

**Detail:** §18.5 defines when a notification is dismissed (by an action with `dismiss: true`, after safe admission) and §18.6:2427 notes that user dismissal of a reminder "MUST NOT dispatch an action" — but nothing anywhere states the effect of dismissal, by either route, on the underlying `notification:*` SURFACE. §13.5:1131-1132 says "The Companion MUST persist the latest accepted snapshot for each present surface and SHOULD render it while Emacs is disconnected", and §13.1/§13.3 make `present` a function of snapshot-vs-tombstone, which a local dismissal does not change — only `surface.remove` creates a tombstone. So a dismissed notification remains a present, persisted surface with a live snapshot and a §13.5 SHOULD-render obligation, and the SPEC never says whether the Companion re-posts it after process restart or reconnection, whether it counts against `max_surfaces` (§13.1:1012, "counts only currently present snapshots"), or whether the welcome's `surfaces` entry still reports `present: true`. Emacs has no signal that the user dismissed anything, so it cannot retire the surface itself.

**Failure scenario:** Emacs pushes `notification:agenda` at 08:00. The user swipes it away at 09:00. Emacs disconnects at 10:00. The Companion process is killed and restarted at 11:00 and, honoring §13.5's "SHOULD render it while Emacs is disconnected" for the still-present persisted snapshot, re-posts the notification — a dismissed alert reappearing hours later with no new information. A second Companion records local dismissal state and does not re-post, but then still reports `{"revision":7,"present":true}` in the next welcome, so Emacs believes the notification is on screen and suppresses a re-push that the user would actually want. Both behaviors conform to the current text; neither endpoint can tell which it is talking to.

**Proposed fix:** Add a paragraph to §18.5 (cross-referenced from §13.5) defining dismissal as a Companion-local presentation state distinct from surface presence: (a) a platform dismissal or a `dismiss: true` action makes the notification not-displayed but does NOT tombstone the surface, does NOT change its revision, and MUST still be reported as `present: true` in the welcome; (b) the Companion MUST NOT re-post a dismissed notification on process restart, reconnection, or the §13.5 disconnected-render path — only a `surface.update` at a higher revision re-posts it; (c) dismissed-but-present surfaces still count against `max_surfaces`; and (d) if Emacs needs to know the notification is gone, it must be modelled explicitly — either state that EBP 2 provides no dismissal report, or define one. Apply the same rule by reference to §18.6 reminder dismissal.

## [P3] [unverified] §18.6 — §18.6 never says which clock a reminder's `at_ms` fires against, nor its behavior under a wall-clock change

**SPEC line:** 2421  
**Auditor:** Audit SS18.5 (notification surfaces: meta, priority monotonicity amend

**SPEC quote:**
> At or after `at_ms`, the Companion MUST present the reminder at most once for that accepted `(owner, id, at_ms)` tuple and MUST persist fired state before or atomically with presentation so a restart does not deliberately re-fire it.

**Detail:** §18.6 gives `at_ms` only as "timestamp / Earliest presentation time" plus this at-most-once sentence. It never names the clock. The SPEC defines two other clocks an implementer could reasonably reach for: §15.2's effective wall clock ("the greater of the current wall clock and a durably stored per-pairing high-water mark"), which governs queue expiry and is explicitly hardened against rollback; and the raw system wall clock. §21.5 needed amendment #47 to pin exactly this question for the structurally identical `time.at_ms` one-shot trigger ("names an absolute wall-clock instant... a forward jump past `at_ms` fires it promptly, and a backward change neither retracts a completed one-shot nor advances an unfired one earlier than `at_ms`"); §18.6 received no parallel sentence, so all three behaviors remain conformant for reminders. §18.6 also never says whether an `at_ms` already in the past at acceptance is valid — "at or after" implies yes, but §21.5 by contrast REQUIRES a trigger's at_ms be later than the wall clock at set acceptance, so an implementer copying the trigger rule would reject it. The reference arms am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at_ms, pi) (Notifications.kt:90) and re-arms from the persisted set on boot/TIME_SET (TriggerAlarms.kt BootReceiver, EbpApplication.kt:23) — one of the three readings, chosen by the implementer rather than by the SPEC.

**Failure scenario:** A reminder is accepted with at_ms = 2026-07-24T15:00 local. At 14:00 the device clock is corrected backward by two hours (NTP or manual). Implementation A (raw RTC, the reference) presents it four real hours later, when the corrected wall clock next reads 15:00. Implementation B (§15.2 effective wall clock with a monotonic high-water mark) presents it one real hour later, since the mark never regresses. Implementation C (elapsed-realtime offset computed at arm time) presents it one real hour later too but then diverges permanently from wall-clock semantics on the next reboot. All three pass every conformance test that exists, and an Emacs agenda setting a meeting reminder cannot know which behavior it will get.

**Proposed fix:** Amend §18.6 with a clock-semantics paragraph mirroring amendment #47: `at_ms` names an absolute wall-clock instant; a pending reminder presents when the effective wall clock first reaches or passes it; a forward jump past `at_ms` presents it promptly (once, per the existing tuple receipt); a backward change neither retracts a committed fired receipt nor advances an unfired reminder earlier than `at_ms`; and an `at_ms` already in the past at acceptance is valid and MUST present promptly (explicitly contrasting §21.5's stricter acceptance rule for `time` triggers).

## [P3] [unverified] §20.3 — SPEC leaves clipboard.read's outcome undefined when the platform's foreground restriction denies the read; success with an empty string is indistinguishable from an empty clipboard

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/AppCapabilities.kt`:83  
**SPEC line:** 2801  
**Auditor:** Audit SS20 (device capability module) against CapabilityCatalog.kt, Co

**SPEC quote:**
> | `clipboard.read` | `{}` | `{text}` | MUST NOT log or persist clipboard content; platform foreground restrictions and the size rule below apply. |

**Detail:** The catalog row acknowledges that "platform foreground restrictions ... apply" but never says what the Companion returns when such a restriction blocks the read. This matters because the dominant platform (Android 10+) does not raise an error for a background clipboard read — `ClipboardManager.getPrimaryClip()` simply returns null. §20.2's taxonomy offers three defensible answers and §20.3 names a `data.reason` token only for the size case (`clipboard-too-large`), so there is no vocabulary for a restriction refusal. Divergent readings: (a) success with `{text:""}` (the platform reported no clip, and §20.1's "stale permission snapshot MAY produce a typed refusal" is only permissive); (b) `1002 cap-permission`, since a foreground restriction is a platform permission condition and §8 says 1002 SHOULD carry `data.permission`; (c) `1003 cap-failed`, since the operation was attempted and did not produce the catalog Result. The reference took (a): readClipboard (AppCapabilities.kt:82-83) collapses `clip == null || clip.itemCount == 0` into `text = ""` and returns Ok. §20.1's "A stale permission snapshot may produce a typed refusal but MUST NOT permit an unauthorized operation" is satisfied either way, so nothing disambiguates.

**Failure scenario:** The Companion UI is backgrounded. Emacs invokes capability.invoke {cap:"clipboard.read"}. Reference behavior: `{"text":""}` — a success the caller cannot distinguish from "the clipboard is genuinely empty". An Emacs command that yanks the device clipboard therefore inserts nothing and reports success, when the correct user-facing outcome is "bring the Companion to the foreground". A second conformant Companion answering 1002 would let Emacs surface that remedy (and, with §8's `data.settings`, offer a settings.open panel). The two behaviors are not interoperable and both claim conformance.

**Proposed fix:** Amend the `clipboard.read` paragraph in §20.3 to pin the restriction case, e.g. after the size rule: "When a platform foreground or focus restriction prevents the Companion from reading the clipboard, it MUST receive `1002 cap-permission` with `data.reason: \"clipboard-restricted\"`; it MUST NOT report success with an empty `text`. An empty `text` MUST mean the clipboard was successfully read and is empty." Add `clipboard-restricted` to the reason vocabulary alongside `clipboard-too-large` and `intent-denied`, and project all three into contract.json.

## [P3] [unverified] §22.1 / §14.1 — No defined Companion behavior for a `when_offline: "wake"` descriptor when `offline.wake` was never granted

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt`:891  
**SPEC line:** 1236  
**Auditor:** Audit SS22 (capability registry and load management: traffic classes, 

**SPEC quote:**
> The safe default is `when_offline: "drop"`. Emacs MUST opt in explicitly to durable replay. It MUST NOT author `wake` unless `offline.wake` was granted.

**Detail:** §22.1 registers `offline.wake` as a negotiated capability meaning "The Companion can attempt the `wake` offline policy", and §14.1 binds only the SENDER ("Emacs MUST NOT author `wake` unless `offline.wake` was granted"). No section states the RECEIVER's duty when a `wake` descriptor arrives without that grant. §12's extensibility rules do not resolve it: rule 6 governs UNKNOWN enum values, but `wake` is a known member of a closed vocabulary; rules 2-3 bind senders. §5.3 constrains what a Companion may do WITH a granted `offline.wake` but says nothing about the ungranted case. The reference exhibits the third reading: `SpecValidator.validateAction` (:891-895) accepts `wake` purely on vocabulary membership with no access to `granted` at all, and `dispatchAction` (CompanionEngine.kt:302-317), `dispatchContextless` (ContextlessEvents.kt:64-78) and `TriggerValidator` (:30, `POLICIES`) all treat `wake` identically to `queue` regardless of the negotiated set — even though DeviceBridge never lists `offline.wake` in `supportedCapabilities` (:60-62). Three divergent conformant readings: (a) reject the containing document with 1201 `content-invalid` (consistent with how every other ungranted feature is handled); (b) silently downgrade the policy to `queue` and admit; (c) honour `wake` fully, since a Companion that never grants it simply has no wake target to signal. The record persists with `"policy":"wake"` (DurableQueue.kt:117), so the reading is observable in the durable store and across a §10.4 reconnection.

**Failure scenario:** A version-skewed or careless Emacs authors `on_tap: {action:"note.capture", when_offline:"wake", ttl_s:3600}` against a Companion whose welcome `granted` omits `offline.wake`. Companion A rejects the whole surface with 1201; Companion B (the reference) applies the surface and durably admits the tap as a `wake` record. Emacs cannot predict which, and a conformance suite cannot score either.

**Proposed fix:** Add one sentence to §14.1 (and mirror it in the §22.1 `offline.wake` row): "A Companion that did not grant `offline.wake` MUST reject a document containing a descriptor whose `when_offline` is `wake` with `1201 content-invalid`; it MUST NOT silently downgrade the policy." Project the rule into contract.json so `validate.py` and generated validators pick it up.

## [P3] [unverified] §22.3 (with §24.6) — §22.3's overload rule pairs a SHOULD-send with a MUST-close whose scope is ambiguous, and its rate limit and exhaustion threshold have no bound, leaving §24.6 item 14 untestable

**SPEC line:** 3313  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 14 th

**SPEC quote:**
> When authenticated processing capacity is exhausted and the endpoint cannot
apply a method's defined safe conflation or retry behavior, it SHOULD send:

**Detail:** Three related gaps sit in one paragraph. (1) Normative scope: §22.3:3313-3314 is a SHOULD, and §22.3:3324 continues "It MUST then close the connection." "then" binds the close to the send, so an endpoint that exercises the SHOULD's discretion and does NOT send `log.error` has no stated closing duty — while a reader who scopes the MUST to the exhaustion condition itself reads the close as unconditional. §22.3:3309-3311's preceding sentence points the other way again: "It MUST apply transport backpressure before unbounded memory growth" — backpressure without closing is a legitimate strategy that the close-always reading forbids. (2) Threshold: "processing capacity is exhausted" is nowhere quantified, and unlike §4.5's limits it is not reported in the welcome, so a peer cannot know or test where it lies. (3) Rate limit: §22.3:3326-3327 says "An endpoint MUST rate-limit `log.error`" with no rate, window, or per-code bound — a MUST with no satisfiable criterion. §24.6:3537 then makes "bounded overload behavior for each traffic class" a REQUIRED adversarial test, but there is no observable normative behavior for a suite to assert: neither whether the connection closes, nor at what load, nor at what diagnostic rate. (This paragraph belongs to the not-yet-built W10 rung, but the defect is in the SPEC text, not the implementation.)

**Failure scenario:** A conformance suite floods a Companion with 50,000 `state.changed`-generating interactions to exercise §24.6 item 14. Companion A applies TCP backpressure, never emits `log.error`, and never closes — it argues §22.3's close is the tail of a SHOULD it declined and that §22.3:3309-3311's backpressure duty is what it satisfied. Companion B emits one `log.error{code:1401}` and closes, dropping the session and every outstanding request. The suite cannot mark either non-conforming, and cannot assert on the rate limit at all because no rate is specified. Two implementations with opposite observable behavior under identical load both pass.

**Proposed fix:** Split §22.3's paragraph. (1) Make the close unconditional and independent of the diagnostic: "When authenticated processing capacity is exhausted and the endpoint cannot apply a method's defined safe conflation or retry behavior, it MUST close the connection, and SHOULD first send the `log.error` shown below." (2) Define exhaustion observably: require each endpoint to bound its inbound frame queue, parsed-message queue, outstanding request count, and per-module work queues at values it can state, and require it to apply transport backpressure first, with the close reserved for the case where backpressure alone cannot prevent unbounded growth. (3) Give the rate limit a floor: e.g. "an endpoint MUST NOT emit more than one `log.error` per second per `data.kind`, and MUST NOT emit `log.error` in response to a `log.error`" (the latter already appears in §8:583-584 and should be cross-referenced). (4) Restate §24.6 item 14 in terms of those observable facts — backpressure before growth, at most one overload `log.error`, then close — so the required test has an assertion.

## [P3] [unverified] §23.3 vs §9.3/§24.5 — §23.3 forbids authentication proofs in Goldens, contradicting the §9.3 known-answer vector and the handshake Golden §24.6 requires

**SPEC line:** 3369  
**Auditor:** Audit SS9 (pairing and mutual authentication) against companion/wire/A

**SPEC quote:**
> Pairing tokens, authentication proofs, password values, clipboard contents, SMS bodies, call numbers, and private editor content MUST NOT appear in normal logs, metrics, diagnostics, Goldens, or crash reports.

**Detail:** §23.3 bans authentication proofs from Goldens without qualification, and §9.1 (SPEC.md:602) bans pairing tokens from Goldens the same way. But §9.3 publishes a normative known-answer vector containing `pairing_token`, `client_proof`, and `server_proof` (SPEC.md:681-686) and requires "A conforming proof implementation MUST reproduce both proof values exactly" (SPEC.md:689); §24.6 item 6 (SPEC.md:3525) requires a suite to cover "the Section 9.3 HMAC known-answer vector plus bad, replayed, and mismatched authentication proofs"; and §24.5 requires a Golden to be "one or more complete wire messages exactly as transmitted" witnessing "the normative rule it witnesses". A handshake Golden therefore cannot exist without proofs in it. The reference repository's own `ebp/goldens/wire/02-handshake.bin` and `ebp/goldens/wire/manifest.json` both carry the two KAT proofs verbatim, i.e. the SPEC's canonical fixture violates the SPEC as literally written.

**Failure scenario:** A conformance reviewer applies §23.3 to `ebp/goldens/wire/02-handshake.bin` and `manifest.json` and must report the reference Goldens non-conformant; an implementer who takes §23.3 literally deletes or redacts the proofs from their handshake Golden and thereby fails §24.6 item 6, which requires the §9.3 KAT to be exercised. Two normative sections cannot both be satisfied.

**Proposed fix:** Amend §23.3 (and the parallel clause at §9.1, SPEC.md:602) with a carve-out: the prohibition applies to values belonging to a real deployed pairing or a real user; the synthetic §9.3 known-answer identity — its token, pairing ID, nonces, and both proofs — is published by this document and MAY appear in Goldens, conformance fixtures, and test sources. Add the reciprocal MUST NOT: an implementation MUST NOT use the §9.3 known-answer token or pairing ID as a live pairing credential in a shipped build.

## [P3] [unverified] §4.1 / §6.2 — §4.1 forbids unpaired surrogate escapes that RFC 8259 permits, but §6.2's error taxonomy assigns them no error class

**SPEC line:** 122  
**Auditor:** Audit SS4.1 through SS4.4 (JSON data model: value types, object/duplic

**SPEC quote:**
> an unpaired surrogate escape is invalid and MUST be rejected rather than preserved or replaced.

**Detail:** RFC 8259 §8.2 explicitly permits member names and string values to contain escapes that do not encode Unicode characters, so a body carrying `"\ud800"` is well-formed RFC 8259 JSON in well-formed UTF-8. §4.1 nonetheless requires rejection. §6.2's post-body taxonomy offers exactly two outcomes — 'invalid UTF-8 or invalid JSON MUST produce a JSON-RPC Parse Error with `id: null`' and 'a top-level array or non-object JSON value MUST produce one Invalid Request response' — and an unpaired surrogate escape is neither invalid UTF-8 (the octets are valid) nor invalid JSON (RFC 8259 allows it). §4.1's neighbouring duplicate-member rule, by contrast, names its class explicitly ('as an invalid request or invalid notification'). An implementer must therefore guess among -32700 Parse Error, -32600 Invalid Request, and 1201 content-invalid, and a conformance suite cannot assert an expected error for the case. Note the same ambiguity applies to the ill-formed-Unicode rule if a lone surrogate arrives inside a string that is otherwise fine.

**Failure scenario:** Two conformant Companions receive `{"jsonrpc":"2.0","id":"1","method":"toast.show","params":{"text":"\ud800"}}`. One answers -32700 with `id: null` and keeps the connection; the other answers -32600 with `id: null`; a third treats it as per-method content and answers 1201 against the request id. All three can claim §4.1 compliance, and a golden fixture for the case cannot state an expectation.

**Proposed fix:** Amend §4.1 to name the class, mirroring the duplicate-member sentence — e.g. 'A body whose decoded strings or member names contain an unpaired surrogate MUST be rejected as a JSON-RPC Parse Error under Section 6.2 (`error.code` -32700 with `id: null` when a response can still be sent safely), because the body is not valid EBP JSON even though RFC 8259 permits the escape.' Add the corresponding negative fixture to goldens/wire and a `kind`/`expect_error` row to the manifest.

## [P3] [unverified] §9.1 — Canonicality of the 22-character base64url pairing token is undefined: 16 distinct display strings decode to the same HMAC key

**SPEC line:** 596  
**Auditor:** Audit SS9 (pairing and mutual authentication) against companion/wire/A

**SPEC quote:**
> The pairing token MUST be displayed as the 22-character [RFC4648] base64url encoding of those 16 octets with `=` padding omitted. Both endpoints MUST decode that exact representation to the original 16 raw octets and MUST use those raw octets as the HMAC key.

**Detail:** 22 base64url characters carry 132 bits but the token is 128 bits, so the final character has 4 unused low bits. RFC 4648 §3.5 leaves it to the specification whether a decoder MUST reject non-zero pad bits; §9.1 never says. Both reference decoders are lenient and I verified it by execution: `EbpAuth.decodePairingToken` (companion/wire/.../Auth.kt:29, `Base64.getUrlDecoder()`) and `ebp-decode-pairing-token` (emacs/ebp.el:352, `base64-decode-string … t`) both map `AAECAwQFBgcICQoLDA0ODw` and `AAECAwQFBgcICQoLDA0ODx` to the identical `000102030405060708090a0b0c0d0e0f`. Strict decoders reject the second (Go's `base64.RawURLEncoding` has rejected non-zero trailing bits since Go 1.15; Rust's `base64` with the default engine likewise). So the 22-character display form is not injective on lenient implementations and is not accepted at all on strict ones — a normative gap an implementer must invent past, with two observably different behaviors.

**Failure scenario:** A user hand-transcribes a displayed token from the phone and mistypes the final character (any of the 16 characters sharing the leading 2 bits works — e.g. `…ODw` typed as `…ODx`). Against the Emacs and JVM reference endpoints the wrong string decodes to the correct key and the handshake succeeds, so the user never learns the transcription was wrong; against a Go- or Rust-based endpoint, or a strict conformance harness, the same string is rejected outright. Two conformant implementations disagree on whether a given printed token is the pairing token.

**Proposed fix:** Amend §9.1 to fix canonicality explicitly, preferably strict: "A decoder MUST reject a 22-character token whose final character encodes non-zero trailing bits; only the canonical encoding of the 16 octets is the token." Add a §9.3 negative vector (`AAECAwQFBgcICQoLDA0ODx` MUST be rejected) alongside the existing KAT so the rule is testable, and note that `=` padding characters MUST also be rejected in the display form.

## [P3] [unverified] §9.1 — §9.1's "MUST rate-limit failed proofs" fixes no rate, window, or persistence, and its per-connection form is vacuous

**SPEC line:** 620  
**Auditor:** Do NOT audit the implementation. Audit the SPEC ITSELF, sections 1 thr

**SPEC quote:**
> The Companion MUST rate-limit failed proofs per pairing ID and source process
or connection.

**Detail:** The requirement names no attempt count, no window, no backoff, and no durability, so it cannot be tested by §24.6's adversarial suite and cannot be failed by any implementation. Worse, the disjunct "or connection" is automatically satisfied: §9.3 requires the Companion to close the connection after every failed proof ("it MUST then close the connection"), so each connection can carry at most one failed proof and a per-connection limiter is a no-op. Readings: (a) per-connection counting satisfies the MUST (the reference: CompanionEngine.kt handleAuth closes on failure and keeps no cross-connection counter); (b) a durable per-pairing-ID counter with backoff surviving process restart is required. The SPEC also never says whether the limiter state must survive Companion restart, nor what the Companion does when the limit trips (refuse the hello — which would violate §9.1's own non-disclosure rule — or delay, or drop the connection silently).

**Failure scenario:** A malicious local app opens a TCP connection to 127.0.0.1:8765, sends a valid hello for a pairing ID it observed, sends a wrong 64-hex proof, is closed, and repeats at several hundred connections per second. Companion A (reading (a)) applies no cross-connection counter and burns CPU and battery indefinitely with no user-visible signal, yet claims conformance because it "rate-limits per connection". Companion B (reading (b)) locks the identity out after 5 failures in 60 seconds. A conformance suite cannot distinguish a conforming from a non-conforming Companion here.

**Proposed fix:** Amend §9.1 to give a floor and a shape: "The Companion MUST maintain a durable failed-proof counter per pairing ID that survives connection close and process restart. It MUST NOT accept more than 10 failed proofs per pairing ID in any 60-second window, and after that MUST apply an increasing delay (at least doubling, capped) before answering a further `auth.response` for that identity. Because Section 9.3 closes the connection on every failed proof, a limiter counted only per connection does not satisfy this requirement. A tripped limiter MUST NOT change the observable hello response (Section 9.1's non-disclosure rule); it delays or drops after `auth.response`." Add the reconnect-loop vector to §24.6.

## [P3] [unverified] §9.2 / §9.3 — "Reused" nonce in §9.3 has no defined scope or enforcing party, and contradicts §9.2's single-connection rule

**SPEC line:** 660  
**Auditor:** Audit SS9 (pairing and mutual authentication) against companion/wire/A

**SPEC quote:**
> Each nonce MUST encode 16 cryptographically random octets as 32 lowercase hexadecimal characters and MUST be used for only one transport connection.

**Detail:** §9.2 states the single-connection rule but assigns it to no one, and §9.3 then makes "a well-formed but reused … nonce" a 1203 condition without saying reused relative to what. Two readings are both defensible. (A) Reused = differs from this connection's pending challenge — this is what `handleAuth` implements (`cn == pendingClientNonce && sn == pendingServerNonce`, CompanionEngine.kt:1520-1521), and it makes the word "reused" redundant with "mismatched". (B) Reused = seen on any previous connection — which would require the Companion to persist every client nonce it has ever been offered (unbounded storage, or a bloom filter with false-positive lockouts), and would require Emacs to persist server nonces to detect a Companion that repeats one. Nothing in §9.1-§9.3 or §23.4 ("Authentication nonces prevent reuse of an old handshake proof on a new connection") picks one. Under reading (A) a client may legally pin one client_nonce forever — which the reference client can do today via the `:client-nonce` config member honored at emacs/ebp.el:611 — while a reading-(B) Companion would 1203 that same client on its second connection.

**Failure scenario:** An Emacs endpoint derives its client_nonce once at startup and reuses it for every reconnection (legal under reading A; the reference `ebp-client-start` will do exactly this if `:client-nonce` is set in the config plist). Against the reference Companion every reconnect succeeds. Against a reading-(B) Companion that remembers client nonces, the second reconnect gets 1203 auth-failed and — because §9.1 forbids distinguishing the cause — the user sees only "authentication failed" and concludes the pairing is broken.

**Proposed fix:** Amend §9.2/§9.3 to state the enforcement boundary explicitly: freshness is a generator-side MUST on each endpoint (a nonce MUST be produced by a CSPRNG for each transport connection and MUST NOT be cached or reused), and the verifier's obligation is exactly to require both nonces to equal this connection's pending challenge — no nonce history is required or permitted as a rejection basis. Delete "reused" from the §9.3 nonce clause (keeping it for proofs, where it is the cross-connection replay case the fresh server nonce already defeats), or define it as "echoed values that do not equal this connection's pending challenge".

---

# TEST findings (10)

## [P2] [unverified] SS24.6 — No test covers a password value on a durable-policy descriptor — the SS24.6 item 12 persistence-exclusion case only tests state.changed and drafts

**Location:** `companion/wire/src/test/kotlin/com/calebc42/ebp/wire/DispatchFieldsTest.kt`:51  
**SPEC line:** 3536  
**Auditor:** Audit SS14.4 through SS14.6 (the event.action request protocol, EventI

**SPEC quote:**
> 12. password-state exclusion from persistence and logs;

**Detail:** The password suite is: ActionEventTest.passwordNodesNeverEmitStateChanged (ActionEventTest.kt:188-210) — no state.changed, no draft, absent from input_state; SurfaceStoreTest's password draft/reset cases; and DispatchFieldsTest's two tests, both of which hard-code `when_offline: "drop"` (DispatchFieldsTest.kt:57 and :82). No test in companion/wire, companion/app, or test/*.el ever dispatches a password-bearing action under `queue` or `wake`, or asserts that the durable queue file never contains a captured password. That is precisely the branch at CompanionEngine.kt:302-308 that is unguarded (see the P1 finding): the DurableQueue admission path for an event whose `fields` carries a secret. The W7 exit gate in docs/REWRITE-PLAN.md claims 'password exclusion (item 12)' as met, but the covered branch is only the state-publication branch.

**Failure scenario:** A regression (or, today, the existing defect) that admits a password into DurableQueue passes the entire 233-test wire suite: nothing asserts on the QueueStore snapshot contents for a secret-bearing dispatch, and nothing exercises dispatchAction with extraFields plus a non-drop policy.

**Proposed fix:** Add a DispatchFieldsTest case: build a READY engine over a FileQueueStore (or a MemoryQueueStore whose snapshot is inspectable), push a password text_input whose on_submit is when_offline queue + ttl_s, call dispatchAction with extraFields {pw:"s3cret"}, and assert (a) no record was admitted (queue.count() == 0), (b) the serialized snapshot contains no occurrence of the secret, and (c) a local diagnostic error reached the callback. Add the mirror case for a dialog.submit capture_fields naming a password, and a validator case asserting 1201 for the queue-policy password descriptor.

## [P2] [unverified] §24.6 / §23.3 — §24.6 item 12 (password exclusion from persistence) is tested only for `when_offline: "drop"` — the durable-admission branch is uncovered

**Location:** `companion/wire/src/test/kotlin/com/calebc42/ebp/wire/DispatchFieldsTest.kt`:51  
**SPEC line:** 3529  
**Auditor:** Audit SS22 (capability registry and load management: traffic classes, 

**SPEC quote:**
> A core conformance suite MUST include at least: … 12. password-state exclusion from persistence and logs;

**Detail:** The whole password corpus is three tests, and every one of them exercises only the non-durable path. `DispatchFieldsTest.passwordSubmitCarriesSecretInFieldsNotArgs` (:51-68) builds `onSubmit` with an explicit `when_offline: "drop"` (:59) and asserts only that the secret lands in `fields` and not `args`. `SurfaceStoreTest.passwordDraftsAreNeverRetained` (:228) covers `putDraft`/`input_state`. `ActionEventTest.passwordNodesNeverEmitStateChanged` (:192) covers `publishState`. Nothing asserts the §14.6 clauses "transmit it without durable admission" / "MUST NOT create an event unless an authenticated READY session exists", and nothing asserts that a descriptor naming a password node with `when_offline: "queue"|"wake"`, `ttl_s`, or `dedupe` is rejected at accept time. The uncovered branch is exactly `CompanionEngine.dispatchAction`'s `"queue", "wake" ->` arm (:303) being reached with a non-null `extraFields`, which is the P1 disk-leak reported above; a single test would have caught it. There is also no test that `SpecValidator` rejects a durable descriptor whose `capture_fields` names a password node (SpecValidator.kt:930-946).

**Failure scenario:** The suite passes green today while `ebp-queue.json` can contain a user's cleartext password: the only assertion that touches password submission pins `when_offline: "drop"`, so no test ever calls `queue.admit` with an `extraFields`-bearing params object, and no test inspects the persisted `QueueSnapshot` for a password key.

**Proposed fix:** Add to DispatchFieldsTest, over a `MemoryQueueStore`-backed engine: (1) `dispatchAction` with `on_submit {when_offline:"queue", ttl_s:3600, capture_fields:["pw"]}` and `extraFields {"pw":"s3cret"}` — assert `queue.count() == 0`, that the callback received the 1201 diagnostic, and that the serialized snapshot contains no occurrence of the secret; (2) a `SpecValidator` test asserting 1201 for a `text_input{password:true}` whose `on_submit` carries `when_offline:"queue"`, and separately for one carrying `dedupe`/`ttl_s`; (3) a `dispatchAction` test asserting that a password-bearing `drop` submission in SYNCING creates no event at all.

## [P2] [unverified] §6.2 — Wire golden corpus's only batch fixture is the empty array, hiding the ebp.el batch-acceptance bug

**Location:** `ebp/goldens/wire/18-batch-array.bin`:1  
**SPEC line:** 447  
**Auditor:** Audit SS4.1 through SS4.4 (JSON data model: value types, object/duplic

**SPEC quote:**
> One frame contains exactly one JSON-RPC Message object. Top-level arrays are prohibited, including JSON-RPC batches.

**Detail:** `18-batch-array.bin` contains exactly `Content-Length: 2\r\n\r\n[]`. That is the one array shape ebp.el's `ebp--parse-body` handles through its `(when (and (null value) ...)` special case (ebp.el:234-236); every non-empty batch escapes through the `(consp (car value))` hole documented in the first finding. The manifest has no fixture for `[{...}]` or `[{...},{...}]` — the literal shape the SPEC sentence names — and `test/ebp-wire-test.el` adds no such case either (its only batch coverage is the manifest replay at lines 82/101/110). The Kotlin side runs the same manifest (WireConformanceTest.wireGoldensBehavePerManifestAtAllChunkings), so the corpus certifies both twins as batch-rejecting while one of them is not. The uncovered branch is precisely: top-level array, non-empty, first element a container.

**Failure scenario:** Add `18b-batch-nonempty.bin` = `Content-Length: 63\r\n\r\n[{"jsonrpc":"2.0","method":"a"},{"jsonrpc":"2.0","method":"b"}]` with `kind: "negative", expect_error: "invalid-request"`. Verified by execution: the Kotlin decoder passes, ebp.el returns OK with a bogus message object and the ERT manifest replay fails — exactly the regression the current corpus cannot see.

**Proposed fix:** Add two negative fixtures to ebp/goldens/wire and the manifest: a one-element batch `[{...}]` and a nested-array top level `[[1]]`, both expecting `invalid-request`. They cost nothing to run (both twins already replay the manifest at all chunkings) and they pin the exact branch the current `[]` fixture cannot reach.

## [P3] [unverified] §13.4 — No test covers §13.4 current-view preservation or the durability of current_view

**Location:** `companion/wire/src/test/kotlin/com/calebc42/ebp/wire/SurfaceStoreTest.kt`:143  
**SPEC line:** 1119  
**Auditor:** Audit SS13.1 through SS13.4 (surface namespaces, surface.update / surf

**SPEC quote:**
> The Companion MUST preserve its current local view across updates while that view still exists. It MUST change views because of an update only when:

- the current view no longer exists, in which case it selects `initial_view`;
- the surface is new, in which case it selects `initial_view`; or
- the request includes `current_view`. (SPEC.md:1119-1125)

**Detail:** `SurfaceStore.currentView(...)` is never asserted anywhere in the suite (grep for `currentView` across companion/wire/src/test and companion/app/src/test returns no call sites; SurfaceStoreTest.multiViewRules at line 143-160 only checks that a bad current_view is rejected and that a stateful stale_spec is rejected, and BuiltinTest exercises view.switch through event emission, not through the stored view). The uncovered branches are the whole `next.currentView = when { ... }` ladder at SurfaceStore.kt:181-187: (a) preservation — `next.present && next.currentView != null && spec.getJSONObject("views").has(next.currentView!!)`; (b) the vanished-view fallback to initial_view; (c) the surface-is-new / reactivated-tombstone fallback. The durable round-trip of `current_view` through FileSurfaceBacking (SurfaceBacking.kt:62, 83) is likewise untested — the one persistence test (SurfaceStoreTest.kt:394-411) uses a single-view spec.

**Failure scenario:** A regression that inverted the preservation guard (for example dropping the `next.present &&` conjunct, or reordering the `currentView != null` branch after the initial_view fallback) would reset every multi-view app surface to `initial_view` on every background refresh — precisely the behavior §13.4 forbids ("Background refreshes SHOULD omit `current_view` so they do not take navigation away from the user") — and the entire 233-test wire suite would still pass. Likewise, dropping `current_view` from FileSurfaceBacking.replace would silently send every user back to initial_view after each process death with no test failure.

**Proposed fix:** Add to SurfaceStoreTest: (1) update a two-view spec, switchView to "detail", re-update with the same views and assert currentView == "detail"; (2) re-update with a spec whose views no longer contain "detail" and assert currentView == initial_view; (3) re-update passing current_view = "list" and assert the request wins; (4) remove() then update() and assert the reactivated surface selects initial_view; (5) extend the FileSurfaceBacking round-trip test with a multi-view surface plus a switchView, and assert the reloaded store reports the same currentView.

## [P3] [unverified] §18.4 — Nothing pins `contract.json` `theme_roles`/`syntax_roles` to the roles the renderer actually resolves and consumes

**Location:** `companion/app/src/test/kotlin/com/calebc42/ebp/companion/render/ThemeModelTest.kt`:74  
**SPEC line:** 2325  
**Auditor:** Audit SS18.4 (theme.set, color roles, dark tri-state/follow-system fro

**SPEC quote:**
> These are projected into `contract.json` as `syntax_roles`, parallel to `theme_roles`.

**Detail:** `WireConformanceTest.kt` pins METHOD_REGISTRY, node schema, and limits against `contract.json`, but grep for `theme_roles`/`syntax_roles` in the whole test tree returns nothing. `ThemeModelTest.resolveColorResolvesSuccessWarningFromExtended` (ThemeModelTest.kt:74-83) exercises exactly three role names (`success`, `warning`, and the unknown-role fallback); no test enumerates the contract's 25 `theme_roles`. `SyntaxHighlightTest.emacsSyntaxColorsOverlaysFgAndKeepsFallback` (SyntaxHighlightTest.kt:44-59) pushes only `keyword` and `string`; no test pushes a role the impl does not implement, and none asserts that a non-standard role is ignored. These two absent branches are precisely the ones that hide findings 1 and 2: `resolveColorIn(scheme, "tertiary_container")` silently returning `scheme.onSurface`, and `emacsSyntaxColors(JSONObject().put("tag", …), fallback)` returning the fallback unchanged while `emacsSyntaxColors(JSONObject().put("paren", …), fallback)` changes rendering. Both defects survived three prior audits and the amendment-#57 contract bump (c5165e5) undetected.

**Failure scenario:** Adding a role to `contract.json` `theme_roles` or `syntax_roles` — as amendment #57 did on 2026-07-23 — produces a fully green build (`c5165e5 contract: bump ebp submodule to 4f6f82b (amendments 51-62)` touched no renderer file) even though the renderer resolves none of the new names. The drift is only observable by eye on a device with a theme that happens to use the missing role.

**Proposed fix:** Add two contract-driven pin tests. (1) In ThemeModelTest: read `theme_roles` from `ebp/contract.json`, and for each role assert `resolveColorIn(lightColorScheme(), role, ExtendedColors.defaults(false))` is not `lightColorScheme().onSurface` unless the role IS `on_surface` — i.e. every contract role has a real mapping. (2) In SyntaxHighlightTest: assert the set of keys `emacsSyntaxColors` reacts to equals `syntax_roles` exactly, by pushing each contract role in turn (expect a change) and pushing `meta`/`paren`/`bogus` (expect `emacsSyntaxColors(map, fallback) == fallback`).

## [P3] [unverified] §19.3 — edit.caret has no emitter and no test: the Companion→Emacs caret/selection path and its throttling are entirely unexercised

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:1152  
**SPEC line:** 2577  
**Auditor:** Audit SS17.7 (editor toolbar: snippets, substitution tokens, placement

**SPEC quote:**
> `edit.caret` contains `document`, `editor_id`, `session`, `seq`, `cursor`, and optional paired `sel_start` and `sel_end`. It is accepted only when `session` and `seq` match. … The Companion SHOULD throttle caret reporting at the source; an intermediate position it never emits is not conflation under Section 22.2, which governs only messages already emitted.

**Detail:** `localEditorCaret` (CompanionEngine.kt:1152-1161) is the only place `edit.caret` is ever emitted, and it has zero callers: grep over companion/app and companion/wire (main + test) finds the declaration and MethodRegistry entry only. RenderEditor's `commit` short-circuits on a selection-only change (`if (new.text != old)`, Renderer.kt:339) and there is no other selection observer, so moving the caret in the Android editor never reaches the engine. Uncovered branches: the OPEN+READY gate (line 1155), the setCaret validation path that drops an invalid caret without emitting (line 1156), and the paired sel_start/sel_end emission at line 1159 — none is executed by any of the 233 wire tests (EditorTest/EditorLifecycleTest have no caret case). The consequence is observable: Emacs's mirror `:cursor` set at edit.open never advances (ebp.el:1010-1016 handles the notification that never arrives), so any Emacs-side feature keyed on the Companion's caret — eldoc/diagnostics targeting, completion context — sees position 0 for the life of the session. Because there is no caller, the §19.3 throttling SHOULD has no implementation to test either.

**Failure scenario:** A synchronized editor opens at cursor 0. The user taps to place the caret at offset 120 and long-presses to select 120..135, then triggers an Emacs-side eldoc/diagnostic flow. No edit.caret is ever emitted, so Emacs computes context at offset 0 and returns documentation for the wrong symbol; a regression in the paired-selection emission or the seq gate would be invisible to CI because no test drives localEditorCaret at all.

**Proposed fix:** Add a Renderer selection observer that calls a throttled bridge.editorCaret (coalescing to the latest position on a ~100ms timer, per §19.3's source-throttle SHOULD) with SCALAR offsets (see the §19.1 UTF-16 finding), and add EditorTest cases for: caret emitted with matching session/seq and paired sel_start/sel_end; caret dropped when the session is not OPEN or the connection is not READY; caret dropped (nothing emitted) when setCaret rejects an out-of-range or unpaired selection.

## [P3] [unverified] §24.4 — Nothing machine-checks §11's State or Capability columns: validate.py's registry sync compares only sender and class, and MethodSpec has no capability field

**Location:** `ebp/validate.py`:115  
**SPEC line:** 3477  
**Auditor:** Audit SS11 (method registry) and SS12 (versioning and compatibility). 

**SPEC quote:**
> - each method's sender, class, legal states, capability gate, params, result,
  and permitted errors; and

**Detail:** There are two registry pins and both have a hole exactly where §11's last two columns live.

(1) SPEC.md §11 -> contract.json is checked by validate.py:114-133. Its regex captures three groups only — ``^\| `([a-z_.]+)` \| (Emacs|Companion|Either) \| (request|notification) \|`` — and the loop at :119-131 compares `sender` and `class` and nothing else. The State column (`CONNECTED`, `CHALLENGED`, `SYNCING`, `S, R`, `R`) and the Capability column (`core`, `surfaces.dialog`, `presentation.toast`, `editor.sync`, …) are never parsed. So contract.json's `states` array and `capability` string are, today, unverified against the law they project.

(2) contract.json -> Kotlin is checked by CompanionEngineTest.methodRegistryMatchesContract (CompanionEngineTest.kt:355-372), which does pin key set, sender, class and `states`. It cannot pin `capability`, because MethodSpec (MethodRegistry.kt:8-12) declares only `sender`, `isRequest`, `states` — the file's own header comment ("Mirrors ebp/contract.json (format 6); WireConformanceTest pins the two together so registry drift is a test failure") therefore overstates the coverage, and also names the wrong test class.

The combined consequence: `states` is pinned contract->Kotlin but not SPEC->contract, and `capability` is pinned nowhere at all, existing only as six scattered `"cap" !in granted` string literals in CompanionEngine.kt (:734, :759, :870, :1004, :1064, :1209, :1253, :1319, :1339, :1371, :1403) with no structural link to the registry.

**Failure scenario:** Concretely uncovered branch: `theme.set`'s legal states. SPEC.md:936 declares it `S, R`; contract.json declares `states: ["SYNCING","READY"]`; MethodRegistry.kt:31 declares `SR`; and that value is what drives the live drop at CompanionEngine.kt:700 (`if (state !in spec.states) return`). Edit SPEC.md:936 to say `R` (as an amendment tightening theme to READY-only) and change nothing else: validate.py still prints "SPEC §8/§11 in sync", methodRegistryMatchesContract still passes (contract and Kotlin agree with each other), and the Companion keeps accepting `theme.set` during SYNCING in violation of the amended §11 — with the whole toolchain green. The Capability column is worse: delete `presentation.toast` from SPEC.md:934 and no test anywhere notices that CompanionEngine.kt:1371 still gates on it, or vice versa.

**Proposed fix:** Extend validate.py's §11 regex to five groups (method, sender, class, state, capability) and normalize the state cell (`S, R` -> `["SYNCING","READY"]`, `R` -> `["READY"]`, backticked single states verbatim), asserting equality with `METHODS[m]["states"]`; assert `METHODS[m]["capability"]` matches the capability cell under an explicit alias map for the two prose cells (`core / surface capability` -> `core-or-surface-capability`, `core for reported surfaces` -> `core`). Add `val capability: String?` to MethodSpec, populate it from §11, extend CompanionEngineTest.methodRegistryMatchesContract to assert it, and drive the ungranted check from `spec.capability` in handleRequest/handleNotification so the enforcement site and the registry cannot drift. Fix the MethodRegistry.kt header comment to name CompanionEngineTest and to state what is and is not pinned.

## [P3] [unverified] §24.6 — No golden or unit test covers a recoverable-error frame pipelined with a valid frame in one read — the branch that hides both stranding defects

**Location:** `ebp/goldens/wire/manifest.json`:1  
**SPEC line:** 3512  
**Auditor:** Audit SS5 (transport profiles) and SS6 (Content-Length framing) agains

**SPEC quote:**
> A core conformance suite MUST include at least:

1. a non-ASCII UTF-8 body whose `Content-Length` differs from its character
   count;
2. two frames with no delimiter between the first body and next header;
3. partial headers, partial bodies, invalid lengths, duplicate lengths,
   oversized declarations, invalid UTF-8, invalid JSON, over-deep JSON nesting,
   duplicate members, and prohibited batch arrays;

**Detail:** The wire corpus satisfies items 2 and 3 only in isolation: 02-handshake.bin is four *valid* pipelined frames, and 10-21 are each a single *bad* frame. No fixture mixes them, so neither `[valid][bad]` nor `[bad][valid]` in one read is exercised. On the Kotlin side, `WireConformanceTest.runFixture` (WireConformanceTest.kt:63-73) collects only via `decoder.feed(it)` and CompanionEngineTest never feeds a malformed frame concatenated with a good one to `engine.feed` (every call is `engine.feed(frame(...))`, one well-formed frame at a time — grep of CompanionEngineTest.kt shows no -32700/-32600 framing assertion at all). On the elisp side `ebp-test--run-fixture-chunked` (ebp-wire-test.el:105-112) has the same shape. That is exactly why the CompanionEngine drain gap and the ebp.el message-loss defect above are both invisible to a green suite.

**Failure scenario:** A regression that reorders `FrameDecoder.feed`'s buffer advance to after `parseBody` (desynchronizing the stream on every recoverable error) leaves all 233 wire tests and all 26 ERT tests green, because no fixture ever places a frame behind a bad one. Likewise the two stranding defects reported above ship with a fully green suite.

**Proposed fix:** Add two wire goldens with a new manifest key (e.g. `expect_messages_before_error`): `22-valid-then-parse-error.bin` = a valid `session.ready` frame immediately followed by an invalid-JSON frame, asserting the valid message is delivered *and* `parse-error` is reported; and `23-parse-error-then-valid.bin` = the reverse, asserting `parse-error` is reported and the trailing valid frame is subsequently delivered without further input. Teach validate.py, WireConformanceTest, and ebp-wire-test.el the new key, and add a CompanionEngineTest case feeding `frame(bad) + frame(request("s2", "session.ready", {}))` in a single `engine.feed` that asserts both a `-32700` and a response for `s2`.

## [P3] [unverified] §24.6 — No test covers §24.6 item 12 for the durable-queue branch: password exclusion is tested only for when_offline:"drop"

**Location:** `companion/wire/src/test/kotlin/com/calebc42/ebp/wire/DispatchFieldsTest.kt`:51  
**SPEC line:** 3534  
**Auditor:** Audit SS15 (durable queue and replay) against DurableQueue.kt, QueueSt

**SPEC quote:**
> 12. password-state exclusion from persistence and logs;

**Detail:** §24.6 makes password-state exclusion from persistence a REQUIRED adversarial test. Existing coverage exercises only the branches that already pass: `DispatchFieldsTest.passwordSubmitCarriesSecretInFieldsNotArgs` (DispatchFieldsTest.kt:51-58) builds "a drop action carrying the secret via extraFields" per its own comment; `SurfaceStoreTest.passwordDraftsAreNeverRetained` (SurfaceStoreTest.kt:228) covers `putDraft`; `ActionEventTest.passwordNodesNeverEmitStateChanged` (ActionEventTest.kt:192) covers `state.changed`. No test in `W6QueueTest.kt` (the §15 suite: `killBeforeDeliveryReplaysAfterRestart`, `dedupeReplacesOlderButNeverInFlight`, `capacityRejectsAdmissionWithoutClaimingQueued`, `oversizedEventIsRefusedLocallyNeverPersistedOrSent`, …) or in `SpecValidatorCompletenessTest.kt` asserts anything about a password node whose `on_submit` carries `when_offline: "queue"`. That uncovered branch — validator acceptance plus `dispatchAction` → `queue.admit` → `QueueStore.replace` — is exactly the one that leaks (see the P1 finding).

**Failure scenario:** The suite passes today while `SpecValidator` accepts `{"t":"text_input","id":"pw","password":true,"on_submit":{"action":"a.b","when_offline":"queue","ttl_s":60}}` and `CompanionEngine.dispatchAction` persists the secret into the `MemoryQueueStore`/`FileQueueStore` snapshot. Any regression in a future password guard would likewise go undetected, because nothing asserts on the store's serialized contents after a password submission.

**Proposed fix:** Add to `W6QueueTest.kt`: (a) `passwordDescriptorWithDurablePolicyIsRejectedAtAcceptTime` — feed a `surface.update` with the spec above and assert a `1201 content-invalid` response naming the `on_submit` path; (b) `passwordSubmitNeverReachesTheQueueStore` — accept a drop-policy password surface, dispatch via `dispatchAction(..., extraFields = {"pw":"hunter2"})` while not READY, then assert `store.load().records` is empty and that the serialized snapshot string does not contain "hunter2"; (c) the same assertion after a forced `AdmitResult.StorageFailed` rollback, so the failure path is covered too.

## [P3] [unverified] §9.1 — The unknown-pairing-ID branch of handleAuth is never exercised; the test that claims to cover it uses a known ID

**Location:** `companion/wire/src/test/kotlin/com/calebc42/ebp/wire/CompanionEngineTest.kt`:139  
**SPEC line:** 621  
**Auditor:** Audit SS9 (pairing and mutual authentication) against companion/wire/A

**SPEC quote:**
> It MUST NOT reveal whether an unknown pairing ID or an incorrect proof caused authentication failure.

**Detail:** `badProofFailsClosedWithoutDistinguishingCause` (line 139) is commented "Unknown pairing ID and wrong proof must be indistinguishable: 1203", but it only sends `hello()` (which always carries `katPid`, lines 71-73) with a corrupted `client_proof`. Every handshake test in the file uses `katPid`, which is the sole key of the engine's `pairings` map (line 45). Consequently the `token != null` conjunct in `handleAuth` (CompanionEngine.kt:1519-1522) is never false in any test, and the §9.1 duty that `handleHello` still issue a normal `server_nonce` challenge for an unrecognized pairing ID — rather than short-circuiting with an error — has no coverage at all. `handleHello` (CompanionEngine.kt:1470-1503) never consults `config.pairings`, which is correct, but nothing pins that behavior.

**Failure scenario:** A future refactor adds the natural-looking early exit `if (pairingId !in config.pairings) return respondError(id, 1203, …)` to `handleHello`, or changes `handleAuth` to answer -32602 when `config.pairings[pendingPairingId] == null`. Both leak whether a pairing ID is provisioned and both leave the entire 233-test wire suite green, because no test ever presents an unprovisioned pairing ID.

**Proposed fix:** Add an engine test that feeds `session.hello` with an unprovisioned pairing ID (e.g. `"ffffffffffffffffffffffffffffffff"`) and asserts (a) the hello result is a well-formed `server_nonce` and the state is CHALLENGED — identical to the known-ID path — and (b) a subsequent well-formed `auth.response` gets exactly the same `{code:1203, message, data.kind}` object and the same CLOSED state as `badProofFailsClosedWithoutDistinguishingCause` produces, asserted by comparing the two serialized error objects rather than just the code.

---

# PLANNED-GAP findings (7)

## [P2] [unverified] §11 — `log.error` is a §11-registered, §24.1-required core method that neither endpoint sends on the mandated paths or handles on receipt (W10)

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:703  
**SPEC line:** 950  
**Auditor:** Audit SS11 (method registry) and SS12 (versioning and compatibility). 

**SPEC quote:**
> | `log.error` | Either | notification | S, R | core | 8, 22.3 |

**Detail:** §11 registers `log.error` as an Either-sender, S+R, core notification, and §24.1 (SPEC.md:3421-3422) names it among the methods a core Companion MUST implement: "`session.ready`, `surface.update`, `surface.remove`, `queue.replay`, `event.action`, `state.changed`, `log.error`, and `rpc.cancel`". Current state, matching the stated W10 boundary (§22 traffic classes / bounded processing / log.error protocol):

- INBOUND, Companion: `handleNotification` (CompanionEngine.kt:692-722) resolves `log.error` from METHOD_REGISTRY and passes the sender/class/state gates, then falls off the end of the `when(method)` at :706-721 with no branch — silently dropped, no local surfacing, no rate accounting.
- INBOUND, Emacs: ebp.el has no `log.error` handler; `ebp-client--notification-dispatcher` (emacs/ebp.el:790-792) logs "unknown notification log.error ignored", misclassifying a registered method as unknown.
- OUTBOUND, mandated path: §7.3 (SPEC.md:513-514) "Structurally invalid notification parameters MUST be reported through `log.error` when authenticated and otherwise MUST be logged and dropped." CompanionEngine.kt:703 is `val params = rawParams as? JSONObject ?: return` — an authenticated drop with no report, and its own comment concedes it ("a notification has no id to answer (log.error arrives with W9)"). ebp.el has no log.error sender at all.
- OUTBOUND, ad hoc: the engine already emits log.error opportunistically at CompanionEngine.kt:533-536 (unknown event.action status) and :746-750 (pie-menu limit, with the comment "rate limiting is W9"), so the wire shape exists but the §22.3 rate-limiting and §8 "MUST NOT recursively answer a malformed `log.error` with another `log.error`" rules that govern it do not.

Also within this gap: §24.1's `rpc.cancel` is implemented on the Companion (CompanionEngine.kt:707-714, dialogs only) but ebp.el neither sends nor handles it, so a Companion-originated cancellation of an outstanding `event.action` or `edit.complete` would be logged as an unknown notification. That one is only a §7.5 SHOULD ("The receiver SHOULD stop work when cancellation is safe"), so it is not itself a defect.

**Failure scenario:** With W10 unbuilt: the Companion, authenticated and in READY, receives `{"jsonrpc":"2.0","method":"toast.show","params":["hi"]}` (params as an array — structurally invalid for a notification). §7.3 requires a `log.error` report to the peer because the session is authenticated. CompanionEngine.kt:703 returns silently, so Emacs never learns its notification was malformed and keeps emitting the same broken frames indefinitely with no feedback channel. Symmetrically, a Companion that does emit `log.error` (this one already does at CompanionEngine.kt:533/:746) gets no reaction from ebp.el beyond a "unknown notification" message.

**Proposed fix:** Deferred to W10 as planned. When it lands: (a) add a `"log.error" ->` branch to CompanionEngine.handleNotification that validates `{code, message, data.kind}` per §8 and surfaces it locally without ever replying with another log.error; (b) replace the silent `?: return` at CompanionEngine.kt:703 with an emitted `log.error` carrying `-32602`/`invalid-params` plus the offending method name, guarded by the §22.3 rate limiter and by a recursion guard for `method == "log.error"`; (c) register a `log.error` handler and add an `ebp-client-log-error` sender in ebp.el, wiring the same §7.3 report for malformed inbound notifications; (d) route the two existing ad hoc emit sites (CompanionEngine.kt:533, :746) through the rate limiter.

## [P2] [unverified] §22.3 — §22.3 bounded processing, the 1401 `overloaded` close, and `log.error` rate limiting are entirely absent (W10) — with three live, unlimited `log.error` emit sites today

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:182  
**SPEC line:** 3309  
**Auditor:** Audit SS22 (capability registry and load management: traffic classes, 

**SPEC quote:**
> Every endpoint MUST bound its inbound frame queue, parsed-message queue, outstanding request count, and module-specific work queues. It MUST apply transport backpressure before unbounded memory growth. … It MUST then close the connection. Outstanding requests fail locally and durable events without permanent results remain eligible for replay. An endpoint MUST rate-limit `log.error` and MUST NOT allow diagnostic reporting to become an additional overload source.

**Detail:** PRESENT today: §22.1 registry gating (9 of 12 names in `supportedCapabilities`, DeviceBridge.kt:60-62; ungranted namespaces → 1201 `namespace-not-granted` at CompanionEngine.kt:571-579; ungranted module requests → -32601; ungranted notifications dropped, e.g. :734). §22.2 class 1: surface snapshots are latest-wins by construction (one spec per surface in SurfaceStore) and theme is whole-replacement. §22.2 class 2: `edit.open/delta/caret/close` all go through the single `@Synchronized` `emit` sink, never conflated. §22.2 class 3: `publishState` (:348-366) emits with zero debounce, the §10.3 SYNCING flush (:422-431) runs before `pumpAdvance`, and `event.action` is conflated only by the durable `dedupe` compaction in `DurableQueue.admit` (DurableQueue.kt:127-132). §22.3's final paragraph IS implemented: `queue`/`wake` durably admit before any delivery attempt even while READY (CompanionEngine.kt:302-317, ContextlessEvents.kt:64-78, TriggerFiringService.kt:159-170). ABSENT: (a) outstanding-request count — `private val pending = HashMap<Int, …>` (:182) grows on every `sendRequest` (:186-192), is pruned only by a matching response (:168), and `close()` (:96-152) never fails its entries locally, so callers of `dispatchAction`/`deliverLiveDrop` are silently abandoned on transport loss; (b) the 1401 `{"kind":"overloaded"}` `log.error`-then-close protocol does not exist anywhere (the only 1401 in the tree is the `max_dialogs` reject at :1412); (c) `log.error` rate limiting does not exist, yet three emit sites are live now — :533 (unknown `event.action` status), :746 (pie-menu limit, whose comment still reads "rate limiting is W9"), plus amendment #38's `1400` path; (d) on the Emacs side §24.2's "sender-side resource limits and load management" is unimplemented — ebp.el rents jsonrpc.el, whose `--request-continuations` table is likewise unbounded; (e) §24.6 item 14 ("bounded overload behavior for each traffic class") has no test. Reachability assessment: the inbound frame path is NOT exploitable — `FrameDecoder.feed` is synchronous on the reader thread (no parsed-message queue exists) and its buffer is capped at 8192 header octets (FrameCodec.kt:61-66) plus a ≤4 MiB declared body (:121), so TCP backpressure is the natural bound; `pending` growth is user/device-driven, not peer-driven. The one §22.3 bound that IS peer-reachable and harmful today is `pendingEditors`, reported separately as an IMPL P1.

**Failure scenario:** Today, with W10 unbuilt: an authenticated peer sends N `pie_menu.show` notifications with distinct `menu_id`s while at `max_pie_menus: 1`; the Companion emits N unthrottled `log.error` frames (1:1, so no amplification, but the MUST is unmet). And on any ordinary transport loss the `pending` map is discarded with the engine, so a `drop`-policy `event.action` initiated by a reminder tap never invokes its callback — its caller (`routeNotificationAction`'s `dismiss:true` contract, ContextlessEvents.kt:111-112) waits forever for an admission report that will never arrive.

**Proposed fix:** W10 scope. Cap `pending` (refuse new outbound requests at the cap and apply backpressure); conclude every remaining `pending` callback with a local failure inside `close()` before clearing state; add a shared token-bucket `log.error` emitter used by all sites including amendment #38's 1400; implement the 1401 `{"kind":"overloaded"}` notification followed by a mandatory close; add §24.6 item 14 tests, one per traffic class. Fix `pendingEditors` ahead of W10 — it is exploitable now.

## [P2] [unverified] §23.3 / §9.1 — No pairing-revocation path exists, so §9.1/§23.3's mandatory erase across all five durable artifacts is unimplemented and unspecified in code

**Location:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/CompanionStores.kt`:26  
**SPEC line:** 3375  
**Auditor:** Audit SS22 (capability registry and load management: traffic classes, 

**SPEC quote:**
> Persistent queues and input snapshots MUST use app-private storage. Where a platform provides keystore-backed encrypted storage, sensitive queued trigger data MUST use it. Durable event payloads and captured input snapshots MUST be deleted after permanent disposition, expiry, pairing revocation, or explicit queue clearing.

**Detail:** The three currently-in-force clauses hold: everything lives under `ctx.filesDir` (app-private) — `ebp-queue.json`, `ebp-surfaces.json`, `ebp-reminders.json`, `ebp-triggers.json` (CompanionStores.kt:66-102) and `ebp-theme.json` (DeviceBridge.kt:93); deletion after permanent disposition is `DurableQueue.deleteRecord` (:194-198) and after expiry is `sweepExpired` (:161-178). The keystore clause is currently unreachable rather than violated — `TriggerValidator.ENCRYPTED_IF_QUEUED` (:38) refuses a durable policy for `sms.received`/`call.state`, and `AppCapabilities.TRIGGER_TYPES` (:32) advertises only `battery.level`, `boot`, `time`, `timezone.changed`, so no sensitive source can be registered at all. What is entirely absent is the pairing-revocation limb: the pairing is a hardcoded §9.3 known-answer constant (DeviceBridge.kt:57-59) with no generation, no storage, and no revocation entry point anywhere in the tree, and none of the five backings exposes an erase/clear API — `QueueStore`, `SurfaceBacking`, `ReminderBacking`, `TriggerBacking` all define only `load`/`replace`, and `ebp-theme.json` is not behind any store abstraction at all. REWRITE-PLAN.md:109 defers this to an unbuilt "pairing rung" ("Earmarked: `auth-source` for pairing tokens (SPEC 9.1)"). Flagged so the rung's implementer inherits the complete erase list rather than rediscovering it: §9.1 requires revocation to "erase its token, queued payloads, input drafts, cached surfaces, tombstones, themes, reminders, triggers, and identity-scoped shortcuts" — the raw theme file and the surface TOMBSTONES (which by design outlive everything else, SurfaceBacking.kt:2-4) are the two easiest to miss.

**Failure scenario:** A user re-pairs their phone with a different Emacs host after selling/lending the device. Because no revocation path exists, `ebp-queue.json` (captured `fields` from every unreplayed event), `ebp-surfaces.json` (all cached surface specs plus the complete `input_state` draft map), `ebp-reminders.json`, `ebp-triggers.json` and `ebp-theme.json` all survive intact into the new pairing's state partition, contradicting §9.1's "Re-pairing creates a new pairing ID and an empty state partition."

**Proposed fix:** At the pairing rung: add `fun erase()` to `QueueStore`/`SurfaceBacking`/`ReminderBacking`/`TriggerBacking` (delete the file and reset the in-memory snapshot, including `nextSeq`/`clockHighWater`), put `ebp-theme.json` behind the same interface instead of raw `File` access in DeviceBridge, and add a single `CompanionStores.revoke(pairingId)` that fences new authentication first, closes the live session, then erases all five plus the stored token — in that order, so a crash mid-erase can never leave an authenticable identity pointing at partially-erased state. Add a test asserting every `filesDir` EBP artifact is absent after `revoke()`.

## [P2] [unverified] §7.3 (with §22.3, §6.2, §24.1) — log.error protocol absent: structurally invalid notification params are dropped silently instead of reported, and inbound log.error is ignored

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt`:704  
**SPEC line:** 514  
**Auditor:** Audit SS7 (JSON-RPC 2.0 conventions) and SS8 (error model) in both twi

**SPEC quote:**
> - Structurally invalid notification parameters MUST be reported through
  `log.error` when authenticated and otherwise MUST be logged and dropped.

**Detail:** W10 (§22 traffic classes, bounded processing, log.error protocol) is not built per docs/REWRITE-PLAN.md:22, so this is a planned gap, recorded so the rung's checklist is complete. Three §7/§8-adjacent duties depend on the missing protocol. (1) CompanionEngine.kt:702-704: `val params = rawParams as? JSONObject ?: return` drops a notification with non-object params with no report, even in SYNCING/READY where §7.3 requires a `log.error`; the inline comment concedes it ("log.error arrives with W9") but W9 shipped without it. (2) `log.error` is registered inbound in MethodRegistry.kt:45 and passes every gate in `handleNotification`, but the `when (method)` at CompanionEngine.kt:706-721 has no `log.error` branch, so a peer diagnostic is silently discarded rather than logged — §24.1 lists `log.error` among the methods a conforming Companion MUST implement. (3) §6.2/§8's diagnostic-only `1400 frame-too-large` (amendment #38) is never emitted: `catch (e: FrameClose) { return close(...) }` at CompanionEngine.kt:107 closes silently even on an unambiguous oversized-but-well-formed declaration, where §6.2 says the receiver SHOULD emit one `log.error` naming the fault first (SHOULD-level, so silent close stays conformant — informational). Note the engine already emits ad-hoc `log.error` at CompanionEngine.kt:533-536 and :746-750 with no rate limiter, which §22.3's "An endpoint MUST rate-limit `log.error`" will need to subsume. The Emacs twin has no `log.error` path at all, neither send nor receive.

**Failure scenario:** Post-auth the peer sends `{"jsonrpc":"2.0","method":"theme.set","params":["dark"]}` (a positional array). The Companion returns from `handleNotification` at line 704 with no diagnostic, so the sender never learns its theme push was structurally rejected and keeps re-sending. Symmetrically, an Emacs-sent `log.error` naming a fault the Companion caused is dropped without being logged anywhere.

**Proposed fix:** When W10 lands: at CompanionEngine.kt:704 replace the bare `return` with `notification("log.error", {code:-32602, message:"Invalid notification params", data:{kind:"invalid-params", method:<method>}})`, gated on SYNCING/READY and on a shared rate limiter; add a `"log.error" -> hostLogListener?.invoke(params)` branch to the `when (method)` (never answering it with another `log.error`, per §8's anti-recursion sentence); route the SHOULD-level `1400` through the `FrameClose` catch at line 107 for the unambiguous oversized-declaration / over-cap-header subcases only; and centralize all existing and new emission sites behind one rate-limited helper. Mirror the send side in ebp.el.

## [P3] [unverified] §21.4 — No diagnostic sink for a failed, skipped, or resumed `on_fire` entry

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/TriggerRuntime.kt`:301  
**SPEC line:** 3029  
**Auditor:** Audit SS21 (device trigger module) end to end — SS21.1 trigger.set rep

**SPEC quote:**
> A runtime failure of
one local entry MUST be recorded safely and MUST NOT stop later entries or
cancel an already admitted remote event.

**Detail:** §21.4 requires both "A runtime failure of one local entry MUST be recorded safely" and "A resumed or skipped local entry MUST be recorded as a diagnostic without sensitive arguments." The failure-isolation half is correctly implemented — `catch (_: Exception) { /* isolated per entry */ }` at TriggerRuntime.kt:301 and the typed no-op returns in `TriggerFiringService.executeOnFire` (lines 205-213) — but nothing is recorded anywhere: the exception is discarded, and `recover()`'s `for ((seq, _) in queue.pendingLocalRecords()) queue.clearPendingLocal(seq)` (TriggerFiringService.kt:235) skips the local list with no diagnostic at all. The protocol-level record mechanism is `log.error`, which is §22 / W10 and explicitly not built, so this is a scope gap rather than a defect; the prior W8 audit deferred the same item as a P3 "needs a log sink".

**Failure scenario:** A `queue`-policy trigger with `on_fire:[{"cap":"vibrate","args":{"ms":500}},{"notify":{"text":"charged"}}]` is admitted, the process is killed during entry 1, and on restart `recover()` clears `pending_local` so the remote event is delivered. Entry 2 never ran and entry 1 may or may not have run; Emacs receives the `trigger.fired` event with no indication that either local response was skipped, and no operator-visible record exists on the device either. Diagnosing "my notification didn't appear" is impossible.

**Proposed fix:** When W10 lands §22's `log.error` protocol, emit a diagnostic from both sites: (a) in `TriggerRuntime`'s per-entry catch, record `{trigger_id, type, entry_index, cap_or_notify, reason}` with the substituted `args` OMITTED (§21.4 "without sensitive arguments"); (b) in `TriggerFiringService.recover()`, record one skipped-local diagnostic per cleared `pending_local` record carrying its `event_id` and trigger id. Until then, route both through an injectable `diagnosticSink: ((JSONObject) -> Unit)?` on `TriggerFiringService` so the obligation is met locally and the W10 wiring is a one-line change.

## [P3] [unverified] §6.2 — The §6.2 frame-too-large `1400` pre-close diagnostic (amendment #38) is not emitted by either endpoint

**Location:** `companion/wire/src/main/kotlin/com/calebc42/ebp/wire/FrameCodec.kt`:121  
**SPEC line:** 419  
**Auditor:** Audit SS5 (transport profiles) and SS6 (Content-Length framing) agains

**SPEC quote:**
> Where the session permits `log.error` (the `SYNCING` or `READY` states of Section 11), the receiver SHOULD emit one diagnostic naming the fault immediately before it closes, using the shape and rate limit of Section 22.3

**Detail:** Both size-cap faults that §6.2 declares unambiguous are detected and closed on — `FrameClose("oversized body declaration")` at FrameCodec.kt:121 and `FrameClose("header section too large")` at FrameCodec.kt:62/66, mirrored at ebp.el:214-215 and ebp.el:255-259 — but neither path emits the `log.error` `{code:1400, message:"Frame exceeds size cap", data:{kind:"frame-too-large"}}` notification. A repo-wide grep for `1400|frame-too-large|frameTooLarge` across `companion/wire/src`, `companion/app/src`, `emacs/`, and `test/` returns exactly one hit, and it is the vocabulary entry `contract.json:848-850` — no producer anywhere. Classified PLANNED-GAP because the obligation is SHOULD-level and is defined "using the shape and rate limit of Section 22.3", and docs/REWRITE-PLAN.md:22 assigns "§22 traffic classes, bounded processing, `log.error` protocol" to W10, which is not built; the MUST-close behavior is correct and silent close remains conformant per amendment #38 ("the MUST-close is unchanged and silent close stays conformant"). Note also that neither existing golden reaches the diagnostic's precondition: 15-oversized-declaration.bin and 20-header-too-large.bin are both bare pre-authentication frames, and §6.2 forbids the diagnostic "before authentication".

**Failure scenario:** With a READY session, Emacs sends a `surface.update` whose body is 5 MB (declared `Content-Length: 5242880`). The Companion closes the transport silently. Emacs observes only an EOF and cannot distinguish an oversized frame from a crash, a supersession, or a device sleep, so it retries the same oversized surface on reconnect and closes again — an avoidable loop the `1400` diagnostic exists to break.

**Proposed fix:** When W10 lands the rate-limited `log.error` emitter, thread it into the framing close path: give `FrameClose` a `diagnosable: Boolean` flag set true only for the two complete-well-formed-header faults (`oversized body declaration`, `header section too large`) and false for missing/duplicate `Content-Length`, malformed header line, and `FrameIncomplete`; in `CompanionEngine.feed`'s `catch (e: FrameClose)`, if `e.diagnosable && (state == SYNCING || state == READY)`, emit one rate-limited `log.error` with `code:1400`, `data:{kind:"frame-too-large", bytes, max}` before calling `close(...)`. Add a post-authentication wire/engine test asserting the notification precedes the close and that no `1400` is emitted for the ambiguous faults or before authentication.

## [P3] [unverified] §7.3 — No `log.error` sender: structurally invalid inbound notification params are dropped without the required report

**Location:** `emacs/ebp.el`:941  
**SPEC line:** None  
**Auditor:** Audit emacs/ebp.el as a whole against every SPEC duty assigned to "a c

**SPEC quote:**
> - Structurally invalid notification parameters MUST be reported through
  `log.error` when authenticated and otherwise MUST be logged and dropped.

**Detail:** `log.error` is listed in the §11 registry with sender "Either", and §7.3 SPEC line 514-515 requires an authenticated endpoint to report malformed notification params through it. emacs/ebp.el contains no `log.error` sender and no `log.error` handler; `ebp-client--handle-state-changed` (ebp.el:941-955) silently falls through its `when` guard when `surface`/`revision_seen`/`id` are the wrong types, producing neither a local log line nor a wire report. Per the audit scope this belongs to the unbuilt W10 rung (§22 traffic classes / bounded per-class processing / the `log.error` protocol), so it is recorded as a planned gap rather than a defect. Noted here because the §7.3 obligation is an inbound-dispatch duty of the Emacs endpoint and will need wiring in the same dispatchers this audit covers, alongside §22.3's rate-limiting and §8's "An endpoint MUST NOT recursively answer a malformed `log.error` with another `log.error`."

**Failure scenario:** Companion sends `state.changed {"surface":42,"revision_seen":"7","id":"title","value":"x"}` while READY. `ebp-client--handle-state-changed`'s `(and (stringp surface) (integerp revision) (stringp id))` guard is false, so the function returns nil and nothing at all happens — no local message, no `log.error`. The Companion receives no signal that its notification was malformed and keeps emitting the same shape.

**Proposed fix:** When W10 lands: add `ebp-client-log-error (client code kind &optional context)` emitting the §22.3 `log.error` notification, gate it on `ebp-client--authenticated-p`, rate-limit it per §22.3, and call it from every notification handler's structural-validation failure path (starting with `ebp-client--handle-state-changed` and the `edit.*` handlers). Until then, at minimum emit a local `message` on the dropped-notification path so the "MUST be logged" half of the rule holds.
