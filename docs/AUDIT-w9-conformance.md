# W9 organ-ports conformance audit (renderer + chrome vs EBP 2.0.0-draft)

Date: 2026-07-23. Target: the W9 organ ports (`companion/app/.../render/*`, `Notifications.kt`, and the wire additions `ToolbarEdits.kt`/`ImageGuards.kt`/`SpecValidator` deep rules/viz-limit threading/`editorCommand`/`routeNotificationAction`), commits W9-a … W9-m (`535753a`). Method: 7 parallel adversarial auditors (image-security, render-core, content-input, layout-viz, toolbar-theme, notif-builtins, spec-gaps), then EVERY finding re-verified against the cited code + SPEC by an independent skeptic. 48 findings surfaced; **45 CONFIRMED, 1 PLAUSIBLE, 2 REFUTED**. Spot-checked P1s (#3 password, #8 text_input hooks, #9 order shape, #10 notif builtin) re-confirmed by hand against SPEC §14.3/§17.4/§14.2.

**Verdict:** the renderer is broad and the pin test keeps advertisement==dispatch, but the ports carry real conformance holes: the image loader's SSRF guard is defeatable by DNS rebinding and its 15s deadline is not enforced during the body read (two P1 security/MUST gaps); `text_input` renders passwords in cleartext + persists them and drops its `on_change`/`on_submit` hooks; there is no per-target node-type gate (dialog/notification accept any known type); several inputs corrupt or lose state on same-identity re-push; and `on_reorder`/notification-builtin wire shapes diverge from §14.3/§14.2. 14 SPEC-amendment candidates document holes the port exposed.

Severity: **P1** = security hole / crash / clear MUST violation. **P2** = narrow edge case / robustness / interop. **P3** = minor / latent / fidelity. **SPEC** = amendment candidate.


---

## Implementation findings (31)


### I1 · P1 · [content-input] enum_list selection retained by option INDEX: same-identity re-push with changed options silently corrupts the value

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/InputNodes.kt:245` — SPEC §17.4 enum_list; §13.6 input draft reconciliation; §16.1 presentation identity


RenderEnumList tracks selection as a Set<Int> of option indices in remember(ctx.path, id) (InputNodes.kt:245). seedIndices() runs only on first composition; a same-presentation-identity re-push (§16.1) does not re-key remember, so the index set persists while `options` is re-read fresh (line 231). If the new snapshot removes or reorders options, the retained indices now point at different option values: currentValue() maps each retained index through the NEW options (line 251), and the FilterChip loop (line 267) marks index i selected against the new label. Both the displayed selection and the value published on the next toggle silently change to option values the user never chose.


**Failure:** options v1 = [{label:'A',value:1},{label:'B',value:2},{label:'C',value:3}]; user selects index 1 (value 2). Emacs re-pushes v2 = [{label:'A',value:1},{label:'C',value:3}] (removes B), same key/id. The chip at index 1 is now 'C' and renders as selected; when the user toggles anything, publish() emits value 3 — the user's B selection was silently converted to C with no user action.


**Fix:** Retain selection by option VALUE (compare with jsonValueEquals against the live options on each recomposition) rather than by positional index, discarding retained values absent from the new options, mirroring the tabs invalid-index reset rule.


### I2 · P1 · [content-input] text_input never dispatches on_change or on_submit (advertised node, load-bearing hooks dropped)

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt:219` — SPEC §17.4 text_input members; §14.3 value injection; §14.6 state.changed-then-on_change


text_input is advertised in both the app and dialog profiles (NodeSupport.kt:43,48) and §17.4 lists on_change and on_submit as members with §14.3 value injection. RenderTextInput (Renderer.kt:204-231) only publishes state via ctx.state(id, it) and wires neither on_change (§14.6 requires the action to fire after state.changed with the same logical value) nor on_submit (no keyboardActions/imeAction). A sender that authors these hooks gets no action at all: a search/submit box is inert.


**Failure:** Emacs pushes text_input {id:'q', hint:'Search', on_submit:{action:'note.search'}}. The user types a query and presses the IME action / Enter; nothing dispatches, so note.search never fires and the search cannot be performed from the Companion.


**Fix:** Wire on_submit via KeyboardActions with a suitable ImeAction (dispatch through ctx.action injecting the value), honor clear_on_submit per §14.4, and dispatch on_change (debounced ≤500ms) after the state.changed publication per §14.6. If text_input is intended to stay minimal in W9, drop on_change/on_submit from the advertised text_input surface until implemented.


### I3 · P1 · [image-security] DNS-rebinding TOCTOU: connect() re-resolves the host, never the validated address

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/ImageLoader.kt:60` — SPEC SPEC.md 1832-1834


loadHttps validates the SSRF address set by calling InetAddress.getAllByName(u.host) (line 60-61), but then connects with (u.openConnection() as HttpsURLConnection).connect() (line 63-74), which performs its OWN, independent DNS resolution of u.host at connect time. The connection is never pinned to any address that isBlockedAddress actually inspected. SPEC 17.2 (line 1832-1834) requires rejecting non-public destinations 'Before each connection and after every redirect or DNS resolution' — the whole point being that the address the socket reaches is the one that was checked. Here the checked address and the connected address are two separate resolutions. The in-code comment ('Before each connection AND after each DNS resolution') asserts a guarantee the code does not provide. Android's InetAddress cache is short/disabled and HttpURLConnection resolves at connect, so this is not incidentally mitigated.


**Failure:** Attacker controls DNS for img.evil.com with a ~0s TTL. First lookup (getAllByName) returns a public IP -> isBlockedAddress false -> passes. conn.connect() then re-resolves img.evil.com and the attacker's DNS now answers 169.254.169.254 (or 127.0.0.1 / 10.0.0.5). The Companion fetches the cloud-metadata / internal service and hands the bytes to BitmapFactory; even on decode failure, timing/side effects confirm reachability. Classic DNS-rebinding SSRF against the exact class of addresses 17.2 mandates be rejected.


**Fix:** Resolve once, filter to the allowed InetAddress(es), then connect to a pinned literal address while preserving the Host header and TLS SNI for the original hostname (e.g. open the socket to the validated InetAddress, set setRequestProperty("Host", host) and an SNI-configured SSLSocketFactory). Do not let the URLConnection perform a second unchecked resolution.


### I4 · P1 · [image-security] 15s total deadline is not enforced within a hop or the read loop (slow-drip defeats it)

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/ImageLoader.kt:95` — SPEC SPEC.md 1831


The 15s deadline (line 51) is only tested at the top of each redirect iteration (line 54). readLimited (line 95-107) has no deadline check and readTimeout (8s) only fires when a read() blocks with NO bytes arriving. A server that dribbles >=1 byte every <8s keeps every read() returning promptly, so readTimeout never trips and the total-deadline is never re-checked during the body read. SPEC 17.2 (line 1831) requires the loader 'stop after 15 seconds total' — a clear MUST that this violates. A single hop can also legitimately consume connectTimeout(8s)+readTimeout(8s)=16s > 15s even without an adversary.


**Failure:** Malicious https host passes the address check, returns 200, then sends 1 byte roughly every 7 seconds. Each read() returns within readTimeout, total climbs by 1 byte per 7s, and the 15s deadline is never consulted inside readLimited. To reach max_image_bytes (8 MiB) at that rate takes ~1.8 years; meanwhile the coroutine holds a Dispatchers.IO thread and an open socket indefinitely. Many such image nodes exhaust the IO dispatcher — a MUST-violation and a resource-exhaustion DoS.


**Fix:** Thread the deadline into readLimited and check System.currentTimeMillis() > deadline inside the read loop (and ideally use a wall-clock cancellation, e.g. withTimeout(DEADLINE_MS) around the whole load, plus a per-socket total-time cap). Fail closed when 15s total elapses regardless of per-read progress.


### I5 · P1 · [layout-viz] reorderable_list on_reorder injects bare identifier strings for `order`, not `{key|id}` identity objects

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/LayoutNodes.kt:679` — SPEC SPEC 14.3 (injection table + `order` prose)


On drag completion RenderReorderableList builds `order` as `JSONArray()` filled with `itemKey(it)` (LayoutNodes.kt:604-608, 679-680), where itemKey returns a BARE STRING (the key's or id's value). SPEC 14.3 requires: "`order` … is the complete post-move sequence of direct-child identity objects. Each identity object is closed and contains exactly one of `{key: identifier}` or `{id: identifier}`, choosing `key` when the child has both." The emitted value is therefore the wrong JSON shape (array of strings instead of array of objects) and additionally erases the key-vs-id distinction, so Emacs cannot reconstruct the identity objects the contract promises.


**Failure:** User drags item B (authored as {id:"b"}) above item A (authored as {key:"a"}). Emacs's on_reorder handler receives args.order = ["b","a"] but the contract/§14.3 promise args.order = [{id:"b"},{key:"a"}]. A conformant handler that indexes into identity objects (`(alist-get 'key o)`) sees strings, fails to match, and the reorder is misapplied or dropped.


**Fix:** Emit identity objects: for each authored index build `JSONObject().put("key", keyVal)` when the item has a non-empty `key`, else `JSONObject().put("id", idVal)`, and put those objects into the `order` array. Reuse the same key>id precedence itemKey already applies, but preserve which member matched.


### I6 · P1 · [notif-builtins] Notification action with a builtin on_tap is accepted but throws at tap time

`companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt:241` — SPEC SPEC 14.2 (SPEC.md:1274)


validateNotificationAction only forces a remote on_tap when `input` or `dismiss:true` is present (SpecValidator.kt:241); otherwise it accepts a builtin on_tap, validating only that the builtin name is in the global ACTION_SCHEMA (SpecValidator.kt:272-277). It never checks the builtin against the notification target's advertised builtins array, which is empty (NodeSupport.kt:80 advertises zero notification builtins). SPEC 14.2 (SPEC.md:1274) requires that a builtin absent from the target profile's builtins array / an invalid context reject the containing document. Worse, there is no runtime path to execute a builtin from a notification action: NotificationActionReceiver routes every tap through routeNotificationAction -> dispatchContextless, which unconditionally calls descriptor.getString("action") (ContextlessEvents.kt:41). A builtin descriptor has no `action` member, so getString throws JSONException on the firing executor — the tap is silently lost and an uncaught exception is raised (the surrounding try only runs `finally{pending.finish()}`, no catch).


**Failure:** Emacs sends a notification surface whose meta.actions[0] = {label:"Copy", on_tap:{builtin:"clipboard.copy", text:"x"}} (no input, no dismiss). SpecValidator accepts it (clipboard.copy is in ACTION_SCHEMA). The user taps the action; NotificationActionReceiver -> routeNotificationAction -> dispatchContextless does descriptor.getString("action") -> JSONException; the clipboard copy never happens and the worker task dies with an uncaught exception.


**Fix:** Reject a builtin on_tap in validateNotificationAction (the notification profile advertises no builtins, and there is no context-less builtin execution path) — i.e. require on_tap to be a remote ActionDescriptor for all notification actions, not only when input/dismiss is present. Defensively, guard dispatchContextless against a descriptor lacking `action`.


### I7 · P1 · [render-core] text_input password field is never masked and its secret is persisted via rememberSaveable

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt:204` — SPEC SPEC.md:1969-1978 (17.4 password), 3322/3487 (persistence exclusion)


RenderTextInput (Renderer.kt:204-231) reads id/enabled/value/syntax but completely ignores the `password` member. The field renders as a plain OutlinedTextField with visualTransformation = syntax-or-None, so a text_input authored with password:true shows the typed secret in cleartext. SPEC 17.4 (line 1970): "`password: true` overrides it with a platform-appropriate secret-entry method" — masking is a MUST. Worse, the draft is held in `rememberSaveable(ctx.path, id)` (line 210), whose default autoSaver writes the in-progress value into Android saved-instance-state (persisted to disk on process death). SPEC's password-state persistence exclusion (§14.6; §26 item 12 at line 3487; "password values ... MUST NOT be written to persistence" line 3322) forbids that. text_input is advertised in both the app and dialog profiles, so every password entry point is affected. Note the wire side (SurfaceStore.putDraft/isPasswordNode) correctly refuses password drafts, but the Compose-local mirror does not.


**Failure:** Emacs pushes a login dialog with {t:text_input, id:pw, password:true, on_submit:{...capture_fields:[pw]}}. The user types their password; it is displayed on screen as plaintext (no dots) and, on a configuration change or process recreation, is serialized into the saved-instance-state Bundle where it may hit disk — both a secret-disclosure and a persistence-exclusion violation.


**Fix:** In RenderTextInput, read `password = node.optBoolean("password")`; when true, set keyboardOptions to KeyboardType.Password and apply PasswordVisualTransformation (unless a syntax transform is present, which is nonsensical for a password), and hold the value in a plain `remember` (never `rememberSaveable`) so the secret is never written to saved instance state. Also wire the `keyboard` enum for non-password fields while here.


### I8 · P1 · [render-core] No per-target node_types gate: a known-but-unadvertised node type is accepted and rendered on dialog/notification targets

`companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt:325` — SPEC SPEC.md:1768-1770 (17 intro), 1692-1705 (16.2)


validateSurfaceSpec/walkNode gate node types only against the GLOBAL NODE_SCHEMA (SpecValidator.kt:325 `NODE_SCHEMA.containsKey(...)`), never against the target profile's advertised node_types. The signature (line 82) and every caller — SurfaceStore.update:141 (app/dialog), handleDialogShow:1409 (dialog), validateNotificationSpec:162/171 (notification) — pass no allowed-types set. The renderer's flat when() dispatch (Renderer.kt:115-163) is likewise target-agnostic: RenderDialogRoot -> RenderNode renders any type. Consequently a `chart`, `table`, `lazy_column`, `editor`, `scaffold`, etc. sent on a `dialog` surface (DIALOG_NODE_TYPES advertises none of those) validates cleanly and is fully rendered; a `button`/`image`/`chart` in a `notification` body (NOTIFICATION_NODE_TYPES = text/row/column/box/spacer/divider only) also validates. This violates SPEC 17 intro (line 1768-1770): "A node type not in the applicable surface_profiles.<target>.node_types array MUST be treated as unsupported even if it appears in this section," and the §16.2 sender-gate/degrade contract. (The app profile advertises the full renderer set, so app surfaces are unaffected — the hole is specifically dialog and notification.)


**Failure:** A version-skewed or malicious Emacs sends dialog.show with a body containing a `chart` node (not in the dialog profile). The Companion validates it via full NODE_SCHEMA and RenderDialogRoot renders a full chart the profile never advertised. For a notification body containing an `image`, the validator accepts it though notification advertises neither image nor any image.* feature — reaching functionality outside the advertised contract.


**Fix:** Thread the target profile's advertised node_types into validation (or into the renderer degrade path). In validateNode, when a type is in NODE_SCHEMA but NOT in the active target's advertised set, treat it as unsupported: degrade it to the §16.2 unknown-node path (render `children` as a neutral column, or nothing) rather than applying its per-type schema and dispatching it. Notifications must additionally be gated to NOTIFICATION_NODE_TYPES.


### I9 · P1 · [render-core] Input-widget local state keyed on key-first identityPath, so changing only a `key` erases a compatible draft

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Attributes.kt:77` — SPEC SPEC.md:1674-1679 (16.1 draft identity)


identityPath (Attributes.kt:77-85) resolves key > id > tree-path, matching §16.1 PRESENTATION identity (correct for collapsible/tabs). But every input widget keys its local draft/value on that same key-first ctx.path: text_input rememberSaveable(ctx.path, id) (Renderer.kt:210), editor (243), checkbox (InputNodes.kt:180), switch (200), enum_list (245-247), slider (344/360). SPEC 16.1 (line 1677-1679) carves out input drafts as the deliberate exception: their identity is surface+ID+type+value-schema, and "Changing only a universal `key` MUST NOT erase a compatible draft." Because ctx.path is key-first, adding/changing/removing a text_input's `key` (id unchanged) changes ctx.path, so rememberSaveable resets to the authored value and the user's visible draft vanishes — while the authoritative wire draft in SurfaceStore is retained (reconcileDrafts erases only on id-disappear/reset/type-change/schema-incompat/ack, not on key change), producing a UI-vs-wire desync.


**Failure:** User types into a keyed text_input {id:note, key:a}. Emacs re-pushes the surface changing only that node's key to `b` (same id/type). ctx.path flips from .../k:a to .../k:b, the Compose field resets to the authored value, and the user's typed text disappears from the screen even though input_state/capture_fields still hold it.


**Fix:** Key input-widget local state on a draft identity that excludes the universal key (surface + id, i.e. the §13.6 wire address), not on the key-first ctx.path. Keep ctx.path for genuine presentation state (collapsible/tabs expansion/selection).


### I10 · P1 · [render-core] Disabled (enabled:false) editor still edits and dispatches through its toolbar

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt:258` — SPEC SPEC.md:1911-1917 (17.4 enabled suppression)


RenderEditor's commit closure gates only on read_only (Renderer.kt:258 `if (readOnly) return@commit`) — it never checks `enabled`. The toolbar is rendered unconditionally (276-289) and EditorToolbar is passed no `enabled` flag, so its snippet/line ops call onValueChange=commit, its items call dispatch=ctx.action(it), and its command items call onCommand=ctx.editorCommand — all live even when enabled=false. The OutlinedTextField(enabled=false) suppresses keyboard editing, but the toolbar is an unblocked side channel. SPEC 17.4 (line 1913-1917): "When `enabled` is `false`, the Companion MUST present the platform's disabled affordance and MUST suppress every action and state dispatch from the node." An enabled:false editor with a toolbar violates this.


**Failure:** Emacs pushes {t:editor, id:e, document:d, enabled:false, toolbar:[{icon:bold, snippet:'**'} , {icon:send, on_tap:{action:'x.y'}}]}. The user taps the toolbar snippet button: commit splices text and fires editorEdit (or state.changed); tapping the on_tap item dispatches a remote action — all from a node that MUST suppress every dispatch.


**Fix:** Pass `enabled` into RenderEditor's commit (add `if (!enabled) return@commit`) and into EditorToolbar so its buttons render disabled and its dispatch/onCommand callbacks are suppressed when enabled is false.


### I11 · P2 · [content-input] text_input ignores `password`: plaintext display + state.changed secret leak

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt:204` — SPEC §14.6 (line 1516: password MUST NOT emit state.changed / disk / input_state); §17.4 (password overrides with secret-entry method)


RenderTextInput never reads the `password` member. SpecValidator only rejects a password node that *seeds* a value or has on_change (SpecValidator.kt:384-386); a bare `text_input {id, password:true}` is valid and reaches the renderer. The field is drawn with visualTransformation = None/Syntax (Renderer.kt:222) — no PasswordVisualTransformation / secret-entry method, so the secret is shown in cleartext, violating §17.4 ("password: true overrides it with a platform-appropriate secret-entry method"). Worse, onValueChange unconditionally calls ctx.state(id, it) on every keystroke (Renderer.kt:225). On an `app:*` surface ctx.dialog is null, so ctx.state → bridge.state → engine.publishState → state.changed and retained input_state. §14.6 line 1516: "A node with password:true MUST NOT emit state.changed. Its value MUST NOT be written to disk, included in input_state, logged...". The secret is streamed to Emacs and persisted for welcome input_state.


**Failure:** Emacs pushes an app surface containing a login form with text_input {id:'pw', password:true} (valid: no value, no on_change). The user types 'hunter2'. The Companion (a) displays the password in cleartext and (b) sends state.changed {id:'pw', value:'h'}, {value:'hu'}, ... 'hunter2' to Emacs and stores 'hunter2' in the surface input-state map that is replayed in the next welcome input_state — a direct secret disclosure the MUST forbids.


**Fix:** In RenderTextInput read node.optBoolean("password"); when true apply PasswordVisualTransformation() (ignoring `syntax`), set keyboard options to a secret-entry method, and suppress the state publication entirely (never call ctx.state for a password node — its value may leave only via on_submit/dialog.submit capture_fields per §14.6). Route the value solely through the submit path.


### I12 · P2 · [content-input] menu ignores per-item `enabled`: a disabled MenuItem still dispatches

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/InputNodes.kt:160` — SPEC §17.4 (MenuItem.enabled; disabled inputs suppress dispatch)


§17.4: "A MenuItem MUST contain label and on_tap and MAY contain icon and enabled; enabled defaults to true", and the section header requires disabled inputs to "present the platform's disabled affordance and suppress every action and state dispatch". RenderMenu builds each DropdownMenuItem (InputNodes.kt:160-168) without passing the item's `enabled` — DropdownMenuItem's `enabled` param defaults to true — so a MenuItem authored with enabled:false renders as active and still fires its on_tap on tap. The node-level `enabled` is honored on the opener IconButton (line 152) but item-level enabled is dropped.


**Failure:** Emacs pushes menu {items:[{label:'Delete', on_tap:{action:'x.delete'}, enabled:false}]} to disable a destructive action contextually. The user opens the menu and taps 'Delete'; it appears fully enabled and dispatches x.delete, contradicting the authored disabled state.


**Fix:** Pass enabled = item.optBoolean("enabled", true) to DropdownMenuItem and guard the onClick (only dispatch when enabled).


### I13 · P2 · [image-security] Ambient-credential suppression is inert: setRequestProperty(...,null) does not disable a default CookieHandler/Authenticator/client certs

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/ImageLoader.kt:69` — SPEC SPEC.md 1829-1831


Lines 69-70 setRequestProperty("Cookie", null) / ("Authorization", null) are the entire mechanism for 'No ambient cookies, credentials, client certs, or auth headers' (comment line 68). These calls are no-ops for that purpose: ambient cookies are injected by CookieHandler.getDefault() at connect time (not via a pre-set Cookie header), server/proxy auth is injected by Authenticator.getDefault() on a 401/407, and client certs are presented by the default SSLSocketFactory's KeyManager. None of these are suppressed. SPEC 17.2 (line 1829-1831) states the loader MUST NOT attach ambient cookies, credentials, client certificates, or authorization headers. Today it is only safe because this app installs no default CookieHandler/Authenticator (grep confirms none), which is an accident of current dependencies, not an enforced guarantee.


**Failure:** A transitive library (or a future feature) calls CookieHandler.setDefault(CookieManager) — common in apps that also use HttpURLConnection or WebView. From then on, image.https fetches silently attach the user's stored cookies for the target host (or, via a default Authenticator, cached Basic/proxy credentials), leaking ambient credentials to arbitrary module-authored image URLs — exactly what 17.2 forbids. The two null-header lines give false assurance that this is handled.


**Fix:** Use a connection that structurally cannot pick up ambient credentials: set a per-connection SSLSocketFactory backed by a KeyManager that presents no client cert, and either null the CookieHandler for this fetch or use a stack (e.g. a dedicated OkHttpClient with no CookieJar/Authenticator) that never consults process-global defaults. Do not rely on setRequestProperty(key, null).


### I14 · P2 · [image-security] NAT64 well-known prefix 64:ff9b::/96 not blocked — reaches embedded private IPv4

`companion/wire/src/main/kotlin/com/calebc42/ebp/wire/ImageGuards.kt:45` — SPEC SPEC.md 1834-1835


isBlockedAddress's Inet6 arm (lines 45-48) covers fc00::/7 ULA and ::/96 IPv4-compatible, but not the NAT64 well-known prefix 64:ff9b::/96 (RFC 6052). On a network with a NAT64 gateway (increasingly common on IPv6-only mobile networks / 464XLAT), an address like 64:ff9b::7f00:0001 (= embedded 127.0.0.1) or 64:ff9b::0a00:0005 (= 10.0.0.5) is a globally-scoped IPv6 address — isSiteLocal/isLoopback are all false — that the gateway translates to the embedded private/loopback IPv4. SPEC 17.2 (line 1834-1835) requires rejecting 'other non-public destination addresses'; a NAT64 address embedding a private IPv4 is such a destination.


**Failure:** Device is on an IPv6-only carrier with 464XLAT/NAT64 (well-known prefix). A module emits image url whose DNS AAAA (or literal) is 64:ff9b::0a00:0005. getAllByName returns that Inet6Address; isBlockedAddress returns false; the fetch is NAT64-translated to 10.0.0.5 and reaches an internal host — SSRF past the guard.


**Fix:** In the Inet6 branch, also reject the NAT64 well-known prefix 64:ff9b::/96 (b[0..11] == 00 64 ff 9b 00...) and, defensively, any address whose embedded low-32-bits IPv4 would itself be blocked; likewise reject 64:ff9b:1::/48 local-use NAT64 if configured.


### I15 · P2 · [layout-viz] Notification surface validation drops max_chart_points / max_canvas_ops (viz limits unenforced)

`companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt:171` — SPEC SPEC 4.5 (max_chart_points / max_canvas_ops aggregate per document; MUST enforce before admission)


validateNotificationSpec calls `validateSurfaceSpec(body, "$path.body", maxCaptureFields)` (SpecValidator.kt:171) and `validateSurfaceSpec(it, "stale_spec", maxCaptureFields)` (SurfaceStore.kt:135) WITHOUT the maxChartPoints/maxCanvasOps arguments, so they default to Long.MAX_VALUE. The engine's dialog path (CompanionEngine.kt:1409-1412) and the app surface path (SurfaceStore.kt:141-143) both correctly thread the profile's §4.5 values; the notification path is the lone exception. validateSurfaceSpec still deep-validates chart/canvas nodes structurally (validateChart/validateCanvas run), so an oversized viz node in a notification body is admitted unbounded rather than rejected. §4.5 states these are aggregate counts "across one SurfaceSpec or dialog document" and MUST be enforced "before durable admission." Impact is limited because the notification profile does not advertise chart/canvas (NodeSupport.NOTIFICATION_NODE_TYPES) and Notifications.kt renders only extracted title/body text, so a conforming sender never emits them and they never render — but the validator asymmetrically accepts a nonconforming sender's 1,000,000-op canvas into the stored notification record without limit.


**Failure:** A nonconforming or version-skewed Emacs sends a notification surface.update whose body nests a `canvas` with 500,000 ops. The app surface path would reject this with 1201 exceeds max_canvas_ops; the notification path admits and stores it unbounded (memory pressure, and a §4.5 MUST-enforce gap).


**Fix:** Thread the limits through: give validateNotificationSpec `maxChartPoints`/`maxCanvasOps` parameters and pass them to its inner validateSurfaceSpec calls, and have SurfaceStore.update pass the same maxChartPoints/maxCanvasOps it already holds (fields at SurfaceStore.kt:20-21) to validateNotificationSpec, matching the else-branch.


### I16 · P2 · [layout-viz] tabs shrink-clamp guard `currentPage >= pageCount` can be masked by Compose's own scroll coercion

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/LayoutNodes.kt:400` — SPEC SPEC 17.3 (shrink to invalid retained index MUST select `initial` without emitting on_change)


RenderTabs implements the §17.3 shrink-clamp with `LaunchedEffect(pageCount){ if (pagerState.currentPage >= pageCount){ lastReported = initial; scrollToPage(initial) } }` (LayoutNodes.kt:400-405). This relies on `currentPage` still holding the now-invalid retained index (>= pageCount) when the effect body runs. HorizontalPager coerces its scroll position (and thus currentPage) to `pageCount-1` during the layout pass that follows the pageCount change; if that coercion lands before the LaunchedEffect coroutine resumes, the guard reads a valid `pageCount-1`, is false, and the tabs stay on `pageCount-1` instead of resetting to `initial` — violating the MUST-select-initial rule. In the same window the settle effect (LaunchedEffect(pagerState.settledPage), LayoutNodes.kt:407-414) can observe settledPage=pageCount-1 != lastReported and fire a spurious on_change for a purely server-driven shrink. The correctness depends on effect-vs-measure ordering that the code does not control.


**Failure:** A tabs node with 5 pages, user on page 4, receives a same-identity snapshot with 3 pages. Spec requires landing on `initial` (e.g. 0) silently. If Compose coerces currentPage to 2 before the pageCount effect runs, the guard misses and the view stays on page 2; the settle effect may additionally emit on_change{value:2}, an action the user never took.


**Fix:** Do not depend on the transient invalid currentPage. Track the retained index explicitly and, in LaunchedEffect(pageCount), unconditionally recompute validity against the new pageCount (e.g. compare the last user-settled page to pageCount and, when it is >= pageCount, set lastReported=initial and scrollToPage(initial) before the settle effect can observe a coerced value); gate the settle-effect dispatch on a flag that suppresses the first settle after a pageCount change.


### I17 · P2 · [layout-viz] reorderable_list drag handle keys pointerInput on the mutating `order`, aborting the gesture after the first swap

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/LayoutNodes.kt:640` — SPEC SPEC 17.3 (reorderable_list; drag mechanics)


The drag-handle modifier is `Modifier.pointerInput(pos, order) { detectDragGesturesAfterLongPress(...) }` (LayoutNodes.kt:640). The onDrag callback mutates `order` (LayoutNodes.kt:667-669) on every crossed neighbor. Because `order` is a key of pointerInput, each mutation tears down and relaunches the pointerInput coroutine, cancelling the in-flight detectDragGesturesAfterLongPress. detectDragGesturesAfterLongPress only begins on a fresh down+long-press, so the relaunched detector will not resume the already-down pointer: the drag ends after the first reorder step, onDragEnd never fires for the continued motion, and draggedPos/offset can be left in a stale state.


**Failure:** User long-presses a handle and drags across two neighbors in one motion. After crossing the first neighbor `order` mutates, pointerInput relaunches, the gesture is dropped mid-drag; the item snaps after a single swap and the user must lift and re-grab to move further — and on_reorder may not dispatch if draggedPos is reset without onDragEnd.


**Fix:** Remove `order` (and ideally `pos`) from the pointerInput key so the gesture detector survives local reordering; read the live drag/order state via remembered MutableState/rememberUpdatedState inside the gesture callbacks instead of capturing them through the key.


### I18 · P2 · [notif-builtins] Notification body content never rendered — postSurface walks a non-existent top-level `children`

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/Notifications.kt:154` — SPEC SPEC 13.4 (SPEC.md:1096) / 18.5


Notifications.postSurface extracts the title/body by calling forEachLeaf(spec.optJSONArray("children")). But a notification SurfaceSpec is `{body: Node, meta?}` (SPEC 13.4, SPEC.md:1096; SurfaceStore.spec returns the raw accepted spec unchanged). There is no top-level `children` key — the content lives under `body` (a single Node). optJSONArray("children") therefore returns null, forEachLeaf returns immediately, `title` stays null, and no body lines are collected. Every notification renders with an empty content body and a title that falls back to `surface.substringAfter(':')` (the raw surface-id suffix, Notifications.kt:163) instead of the authored `style==title` text. The 18.5 notification content pipeline is effectively inert.


**Failure:** Emacs sends surface.update for `notification:meeting` with spec `{body:{t:"column",children:[{t:"text",style:"title",text:"Standup"},{t:"text",text:"Room 3, 9am"}]}}`. The posted Android notification shows title "meeting" and no body text; "Standup" and "Room 3, 9am" are dropped because postSurface looked for spec.children (null) rather than descending spec.body.


**Fix:** Walk the notification body node, not a top-level children array: e.g. `forEachLeaf(JSONArray().put(spec.optJSONObject("body")))`, or start from spec.getJSONObject("body") and recurse (forEachLeaf's row/column/box descent already handles a container body; a bare text body is visited directly).


### I19 · P2 · [notif-builtins] Inline reply not bounded by max_field_bytes — only the looser max_event_bytes is checked

`companion/wire/src/main/kotlin/com/calebc42/ebp/wire/ContextlessEvents.kt:116` — SPEC SPEC 18.5 (SPEC.md:2318), SPEC 14.1 (SPEC.md:1246)


SPEC 18.5 (SPEC.md:2318) states an inline reply MUST be bounded by max_field_bytes, and SPEC 14.1 (SPEC.md:1246) says the Companion MUST NOT create an occurrence whose captured field exceeds max_field_bytes. routeNotificationAction places the RemoteInput reply text directly into `fields` under the reply key with no per-field bound; the only size gate is dispatchContextless's check of the whole params object against max_event_bytes. With the advertised limits max_field_bytes=65536 and max_event_bytes=262144 (DeviceBridge.kt:71, CompanionStores.MAX_EVENT_BYTES=262144), a reply between 64KiB and ~256KiB is admitted, producing an event.action.fields value that exceeds max_field_bytes. Android's RemoteInput imposes no length cap, so the oversized field is created and delivered/queued.


**Failure:** A notification inline-reply action is tapped and the user pastes 100 KiB of text. routeNotificationAction builds fields={reply:<100KiB>}; dispatchContextless sees total params (~100KiB) < 262144 max_event_bytes and admits the occurrence. Emacs receives an event.action whose fields.reply exceeds max_field_bytes, the limit that was supposed to protect it.


**Fix:** Thread max_field_bytes into routeNotificationAction and reject/truncate-with-diagnostic when replyText's UTF-8 length exceeds it before building fields (mirroring the 14.1 capture_fields enforcement), rather than relying on the whole-event max_event_bytes check.


### I20 · P2 · [toolbar-theme] A second ${cursor} token leaks as literal "${cursor}" text into the buffer

`companion/wire/src/main/kotlin/com/calebc42/ebp/wire/ToolbarEdits.kt:57` — SPEC SPEC 17.7 snippet placeholders (${cursor} is the Final cursor marker; only unknown ${...} tokens MUST remain literal)


render() handles ${cursor} only under `token == "cursor" && cursor < 0` (line 57). A second ${cursor} occurrence finds cursor >= 0, matches none of the when branches, and falls into the `else -> sb.append(snippet, i, end + 1)` literal branch (line 61), injecting the raw text "${cursor}" into the output. ${selection} avoids this because it has a bare `token == "selection"` fallthrough (line 56); ${cursor} has none. A known placeholder should be consumed (removed), not rendered as garbage — the spec reserves literal passthrough for UNKNOWN tokens only.


**Failure:** Snippet "a${cursor}b${cursor}c" renders to "ab${cursor}c" — the literal string ${cursor} is written into the user's document.


**Fix:** Add a bare `token == "cursor" -> {}` branch (no-op consume) after the `cursor < 0` branch so subsequent cursor tokens are dropped rather than emitted literally.


### I21 · P2 · [toolbar-theme] line-start idempotence check trims whitespace, so it is not the EXACT literal prefix

`companion/wire/src/main/kotlin/com/calebc42/ebp/wire/ToolbarEdits.kt:131` — SPEC SPEC 17.7 (`line-start` MUST no-op when the line already starts with the exact literal inserted prefix)


insertAtLineStart computes want = prefix.trimStart() and tests here.trimStart().startsWith(want). Trimming leading whitespace on both sides means the guard fires when the line's non-whitespace content matches, not when the line begins with the exact literal prefix. It produces false no-ops (an already-indented line suppresses insertion of a top-level prefix) and, when the prefix itself is pure indentation, want becomes empty and the check is skipped so it never no-ops.


**Failure:** Line is "  - foo" (indented bullet), caret on it, toolbar inserts prefix "- " at line-start. want="- "; here.trimStart()="- foo" startsWith "- " → true → no-op. The line does NOT begin with the literal "- " (it begins with spaces), yet the button silently does nothing.


**Fix:** Compare the exact literal: `if (text.regionMatches(lineStart, prefix, 0, prefix.length)) return edit`, dropping the trimStart normalization.


### I22 · P3 · [image-security] IPv4-mapped IPv6 (::ffff:0:0/96) relies on JVM normalization, not an explicit guard

`companion/wire/src/main/kotlin/com/calebc42/ebp/wire/ImageGuards.kt:47` — SPEC SPEC.md 1834


The Inet6 branch checks isIPv4CompatibleAddress (the deprecated ::/96 compat form) but has no check for IPv4-MAPPED addresses ::ffff:a.b.c.d (Inet6Address.isIPv4MappedAddress has no public accessor; there is no explicit test here). Correctness for a mapped address whose embedded IPv4 is private/loopback depends entirely on java.net normalizing a 16-byte ::ffff: address into an Inet4Address (so the isLoopback/isSiteLocal checks catch it). That normalization holds on OpenJDK and current Android libcore, but it is an implicit dependency for a security guard and is not asserted by any test in this stack.


**Failure:** On an Android/libcore build (or future runtime) that returns a mapped AAAA as a genuine Inet6Address rather than converting to Inet4Address, ::ffff:127.0.0.1 would fall through isLoopback/isSiteLocal (all false for the Inet6 object) and through this branch (isIPv4CompatibleAddress is false for mapped), yielding an SSRF bypass to loopback.


**Fix:** Add an explicit mapped-address check: if the 16-byte form has bytes[0..9]==0, bytes[10]==0xFF, bytes[11]==0xFF, extract the embedded IPv4 and run the Inet4 rules on it (rejecting loopback/private/etc.) rather than depending on runtime normalization.


### I23 · P3 · [image-security] Relative and protocol-relative redirect Locations are rejected, breaking legitimate same-origin redirects

`companion/wire/src/main/kotlin/com/calebc42/ebp/wire/ImageGuards.kt:54` — SPEC SPEC.md 1835-1836


redirectAllowed requires the Location to literally start with 'https://' after trim/lowercase. A same-origin relative redirect (Location: /path/img.png) or protocol-relative (Location: //cdn.example/img.png) — both extremely common — fail this test and abort the load. This is fail-safe (no security loss) but harms interop: a well-behaved https server issuing a relative 302 to its own image will render as a broken-image placeholder. SPEC 17.2 (line 1835-1836) only forbids following a redirect to a different URI scheme; it does not require rejecting relative Locations. Separately, there is a benign inconsistency: redirectAllowed trims leading whitespace but the next-iteration isHttps(current) (ImageLoader.kt line 55) does not, so a whitespace-prefixed absolute Location is accepted here then rejected there — the load still fails safe, just via a different path.


**Failure:** A CDN serving a valid image responds 302 with Location: /v2/photo.png (relative, same host, same https scheme). redirectAllowed returns false, load returns null, and the user sees the broken-image glyph instead of a perfectly safe image — an availability/interop regression, not a security issue.


**Fix:** Resolve the Location against the current request URL (URL(base).toURI().resolve(loc)) BEFORE the scheme check, then enforce that the resolved scheme is https and re-run the address checks on the resolved host. Keep the current strict reject only for a resolved scheme other than https.


### I24 · P3 · [image-security] Image limits hardcoded in RenderImage duplicate DeviceBridge's advertised values (drift risk)

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/ContentNodes.kt:71` — SPEC SPEC.md 246-248, 257-258


RenderImage hardcodes ImageLoader.Limits(8_388_608, 67_108_864, 16_777_216) (line 71); DeviceBridge advertises the identical max_image_bytes / max_decoded_image_bytes / max_image_pixels as separate literals (DeviceBridge.kt line 78-80). SPEC 4.5 (line 246-248, 257-258) requires the enforced limits to equal the advertised ones. They match today, but the values live in two hand-kept places with no shared constant or test binding them, unlike the NodeSupport->DeviceBridge derivation used for node types. A future edit to one literal silently diverges enforcement from advertisement.


**Failure:** Someone bumps max_image_pixels in DeviceBridge to advertise a larger capability but forgets ContentNodes.kt (or vice versa). The Companion then advertises a limit it rejects at, or enforces a stricter/looser bound than advertised — a 4.5 conformance violation that no test catches.


**Fix:** Define the three image limits once (e.g. in NodeSupport or a shared constants object) and have both DeviceBridge advertisement and RenderImage's ImageLoader.Limits read from it, with a pin test asserting equality — mirroring the existing NodeSupport surface-profile derivation discipline.


### I25 · P3 · [layout-viz] chart bar/area forces yMin=0 even when an explicit y_range with min>0 is authored

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/VisualizationNodes.kt:107` — SPEC SPEC 17.5 (chart.y_range is authored [min,max])


After applying an authored y_range (VisualizationNodes.kt:104-106), the code unconditionally runs `if ((kind=="bar"||kind=="area") && yMin > 0.0) yMin = 0.0` (VisualizationNodes.kt:107), overriding the author's explicit lower bound. When y_range=[10,20] is authored for a bar chart, yMin is silently reset to 0, so bars are scaled against a baseline the author did not request.


**Failure:** Author sends a bar chart with y_range=[50,100] to zoom into a narrow band; the renderer rescales to [0,100], flattening the visual differences the y_range was meant to emphasize.


**Fix:** Only default the baseline to 0 when no y_range was authored: apply the bar/area yMin=0 clamp before reading y_range, or skip it entirely when node.has("y_range").


### I26 · P3 · [layout-viz] chart on_point_tap maps tap-x by first-series length while points are laid out on maxLen spacing

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/VisualizationNodes.kt:123` — SPEC SPEC 17.5 (on_point_tap returns the authored point at the tapped position)


The tap handler computes idx from `s0.ys.size` (VisualizationNodes.kt:122-124) but the canvas lays out x-positions using `n = maxLen` across all series (VisualizationNodes.kt:133-135, xLine uses maxLen). When the first series is shorter than the longest series, its points are drawn compressed into the left region (i/(maxLen-1)) yet the tap maps the full width onto s0's own length, so the returned point does not correspond to the point drawn under the finger.


**Failure:** series[0] has 3 points, series[1] has 10 points. series[0]'s points render in the left ~30% of the width, but a tap at 90% width returns series[0] point index 2 (its last), which is drawn near 30% — the wrong point object is returned.


**Fix:** Map the tap x using the same denominator the layout uses (maxLen) and select the point by that shared index, or hit-test against the actual drawn point x-positions of the chosen series.


### I27 · P3 · [layout-viz] flow_row ignores `align` (cross-axis run alignment)

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/LayoutNodes.kt:163` — SPEC SPEC 17.3 (flow_row.align is top|center|bottom, default top)


RenderFlowRow (LayoutNodes.kt:163-171) sets horizontalArrangement and a run_spacing verticalArrangement but never reads the `align` member. SPEC 17.3 defines flow_row.align (top/center/bottom, default top) as the cross-axis alignment of items within a run; it is silently dropped, so `align:center`/`bottom` render as top.


**Failure:** A flow_row of chips of differing heights with align:center renders all chips top-aligned within each wrapped run, contradicting the authored vertical centering.


**Fix:** Read `align` and apply Compose FlowRow's per-run cross-axis alignment (itemVerticalAlignment / Alignment.CenterVertically|Bottom|Top) mirroring the row/box alignment mapping.


### I28 · P3 · [layout-viz] row `align: baseline` silently falls back to center

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/LayoutNodes.kt:130` — SPEC SPEC 17.3 (row.align includes `baseline`)


RenderRow maps row.align top->Top, bottom->Bottom, else CenterVertically (LayoutNodes.kt:130-134); `baseline` (an enumerated §17.3 value) hits the else branch and renders as center. The inline comment acknowledges baseline is unimplemented. This is a rendering-fidelity gap for a declared alignment option.


**Failure:** A row mixing large and small text with align:baseline is meant to sit the text on a common baseline; it renders vertically centered instead, misaligning the type.


**Fix:** Implement baseline via per-child Modifier.alignByBaseline() within the Row when align=="baseline", or document the fidelity gap; if unimplementable in this build, treat it as a known §16.4 limitation rather than a silent center.


### I29 · P3 · [notif-builtins] chronometer.base_ms accepted as any Number, not a non-negative integer timestamp

`companion/wire/src/main/kotlin/com/calebc42/ebp/wire/SpecValidator.kt:199` — SPEC SPEC 4.3, SPEC 18.5 (SPEC.md:2299)


validateNotificationMeta validates chronometer.base_ms only with `!is Number` (SpecValidator.kt:199), so a negative value, a fractional value (1.5), or a huge out-of-range value is accepted, contrary to SPEC 4.3 (an epoch timestamp is a non-negative integer). This is inconsistent with validateReminder's at_ms, which is strictly checked for non-negativity and integrality. The presentation side is safe — postSurface guards `baseMs > 0L` (Notifications.kt:171), so base_ms=0/negative simply drops the chronometer and a fractional value is truncated by optLong — so there is no crash or bogus 1970 render, only a missed rejection of malformed input.


**Failure:** Emacs sends meta.chronometer={base_ms:-1000} or {base_ms:1.5}. SpecValidator accepts the surface even though the value is not a valid epoch timestamp; the malformed field is silently ignored at present time rather than rejected at accept time.


**Fix:** Validate base_ms as a non-negative integer timestamp (0..2^53-1, no fractional part) using the same check applied to reminder at_ms.


### I30 · P3 · [render-core] clip:true with a rectangular corner is silently ignored, so overflow clipping is not applied

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Attributes.kt:145` — SPEC SPEC.md:1747 (16.5 clip)


The universal-attribute clip is applied only `if (node.optBoolean("clip") && shape != RectangleShape)` (Attributes.kt:145). When a node sets clip:true without a `corner` (shape == RectangleShape), no clip modifier is applied at all. SPEC 16.5 (line 1747) defines clip as "Clip descendants to the corner shape" — with corner absent/0 the corner shape is the rectangle, and clipping descendants to the node's rectangular bounds is still a meaningful (overflow-suppressing) operation, not a no-op. The guard treats rectangular clip as a no-op, so a node that requests clip:true purely to contain overflowing descendants does not clip them.


**Failure:** A box with fixed width/height, clip:true, no corner, containing a child that draws beyond the box bounds (e.g. an over-wide image or negatively offset content). The spec asks descendants to be clipped to the box; the impl skips clip and the child bleeds outside the box.


**Fix:** Apply clip whenever node.optBoolean("clip") is true, using `shape` (RectangleShape when no corner). Drop the `shape != RectangleShape` half of the guard.


### I31 · P3 · [toolbar-theme] Pushed SyntaxStyle bg/font_weight/italic/underline are silently dropped (only fg honored)

`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/SyntaxHighlight.kt:78` — SPEC SPEC 18.4 (A SyntaxStyle MAY contain fg, bg, font_weight, italic, and underline)


syntaxFg() reads only the `fg` member of each SyntaxStyle object; the SyntaxColors data class carries a single Color per role with no weight/italic/underline/bg. A theme.set `syntax` map that specifies, e.g., bold+italic keyword faces or an underlined link face has those attributes discarded — the tokenizer applies its own hard-coded per-type weight/italic decisions instead of the pushed Emacs face. Emacs theme fidelity is therefore lost for every non-foreground face attribute. The spec models these as optional (MAY), so this is best-effort-conformant, but the divergence is a real fidelity gap worth an explicit conformance note.


**Failure:** Emacs pushes syntax.keyword = {fg:"#81A1C1", font_weight:"bold", italic:true}; the companion renders keywords in that color but with the tokenizer's own weight/style, dropping the italic entirely.


**Fix:** Either extend SyntaxColors to a per-role style (color + weight/italic/underline/bg) applied by the tokenizer, or document in SPEC 18.4 that a Companion MAY honor only `fg` for syntax faces so the limitation is contractual rather than silent.


---

## SPEC-amendment candidates (14)


### S1 · P2 · 16.2 vs 17.1: an unadvertised-but-known node type — reject, degrade, or validate strictly — is contradictory

SPEC SPEC 16.2 / 17.1


16.2 describes the degrade path only for an "unknown node type" (render children as a neutral sequence, or nothing). 17.1 says "A node type not in the applicable node_types array MUST be treated as unsupported even if it appears in this section." These collide for a type the Companion FULLY implements in code but that Emacs did not advertise in this profile: is it (a) validated strictly and rejected with 1201 on any schema error, (b) degraded like an unknown type (children-only, no strict validation), or (c) rendered normally? 16.1's blanket "malformed node... MUST reject the entire update" pulls toward (a); 17.1's "treated as unsupported" pulls toward (b). W9's SpecValidator keys purely on NODE_SCHEMA (the full built vocabulary) with no profile/node_types awareness (walkNode/validateNode, SpecValidator.kt:325,371), so it validates any known type strictly regardless of advertisement — effectively choosing (a)/(c) and never (b).


**Proposed resolution:** State unambiguously, at one layer, what a receiver does with a spec-defined but unadvertised node type: recommend treating it exactly as an unknown type (16.2 degrade, no strict per-type validation), and clarify that 16.1's reject rule applies only to advertised/core types. Note explicitly that validators keyed on the full vocabulary must gate per-type rules on the advertised node_types set.


### S2 · SPEC · No runtime per-form advertisement gate; SpecValidator comment claims one that does not exist

SPEC SPEC.md 1822-1825


SpecValidator.isValidImageUrl accepts BOTH https and data:image regardless of which of image.https / image.data is advertised (comment at SpecValidator.kt line 510-511 asserts 'The per-form advertisement gate ... is runtime'), but RenderImage (ContentNodes.kt line 67-75) and ImageLoader.load (ImageLoader.kt line 35-39) apply no such runtime gate either — any valid form is loaded. This is latent-only because NodeSupport advertises both forms in every profile (NodeSupport.kt line 24). The deeper issue is a SPEC hole: 17.2 (line 1822-1825) obliges Emacs to 'use only an advertised form' but does not state whether the Companion MUST reject an image whose form it did not advertise. A conformant implementer that advertised only image.https could reasonably either reject or silently load a data: image; the spec does not say.


**Proposed resolution:** Amend SPEC 17.2 to state explicitly whether a Companion MUST reject an image whose URI form is not advertised in that profile's features (recommended: MUST reject as content-invalid, mirroring the unadvertised-node-type rule in 16.2). Then have the validator take the advertised feature set and gate isValidImageUrl on it, instead of the comment deferring to a 'runtime' gate that is absent.


### S3 · SPEC · Multiple ${input:...} tokens: spec undefined; impl prompts once and reuses one value

SPEC SPEC 17.7 (${input:Prompt}: One local free-text prompt titled Prompt)


The placeholder table describes ${input:Prompt} as 'One local free-text prompt', but a snippet may syntactically contain several input tokens with different prompt titles. The implementation prompts exactly once using the FIRST token's title (inputPrompt/needsInput read only the first ${input:), then substitutes that single entered value into EVERY input token (render line 60 matches any token starting with 'input:'), so two distinct prompts collapse to one value and only one title is shown. This is defensible but the spec never states whether multiple input tokens are permitted, whether each should prompt separately, or whether they must share a title.


**Proposed resolution:** Amend SPEC 17.7 to either (a) restrict a snippet to at most one ${input:...} token, or (b) require one prompt per distinct token in document order, resolving the ambiguity a conformant implementer would otherwise guess at.


### S4 · SPEC · 'Legible platform fallback' underspecified for partial color palettes with foreign pushed roles

SPEC SPEC 18.4 (The Companion MUST merge missing roles with a legible platform fallback)


buildColorScheme fills a missing on-role from the BASE Material scheme's on-color, which is legible against the base scheme's own container color but not necessarily against the FOREIGN color the theme pushed for the paired role. The code derives a contrast-correct on-color (legibleOn) for success/warning but does NOT do so for the standard on_* roles, so a theme that pushes `primary` (or surface, background, etc.) without its `on_primary` can yield a low-contrast pair. The spec's 'legible platform fallback' does not say whether legibility must hold against the base default or against the pushed sibling color, leaving the required behavior for partial palettes ambiguous.


**Proposed resolution:** Clarify SPEC 18.4: when a role is present but its paired on-color is missing, require the Companion to derive a contrast-legible on-color from the pushed color (as done for success/warning), rather than adopting the base scheme's on-color.


### S5 · SPEC · SPEC priority ladder has 5 levels but Android channels expose only 4 usable importances — `max` and `high` are indistinguishable

SPEC SPEC 18.5 (SPEC.md:2298-2299)


SPEC 18.5 defines five priorities (min|low|default|high|max), but Android NotificationChannel importance has no usable level above IMPORTANCE_HIGH (IMPORTANCE_MAX is deprecated/unused for channels). channelFor collapses both `high` and `max` to IMPORTANCE_HIGH (Notifications.kt:135); they get distinct channel ids but identical, immutable importance, so a user cannot perceive or independently control `max` vs `high`. This is not an implementation defect (the platform offers no finer control) but a portability floor the SPEC should acknowledge so implementers/authors know `max` is best-effort equal to `high` on Android-class platforms.


**Proposed resolution:** Amend SPEC 18.5 to note that priority is a hint and platforms MAY coalesce adjacent levels (notably `high`/`max`) where the OS lacks a distinct channel importance, so authors do not rely on a 5-way distinction.


### S6 · SPEC · 18.4 syntax-role name set is never enumerated (theme roles are, syntax roles are not)

SPEC SPEC 18.4


SPEC 18.4 defines the `syntax` field only as a "Syntax-role to SyntaxStyle map" and says "A SyntaxStyle MAY contain fg: Color, bg: Color, font_weight, italic, and underline" — but nowhere names the syntax-role vocabulary. This is asymmetric with theme colors: 18.4 enumerates the standard theme roles in prose ("Standard roles include primary, on_primary...") and contract.json projects them as `theme_roles` (lines 997-1023), yet the contract has NO `syntax_roles` array and the prose lists none. An implementer literally cannot know which role keys Emacs will send. W9 had to invent its own closed set — comment, string, keyword, function, constant, number, link, meta, todo, done, heading, paren (SyntaxColors, SyntaxHighlight.kt:27-40) — and the file comment openly admits the guess: "Roles are an open set (the contract fixes no syntax_roles); unknown roles are ignored."


**Proposed resolution:** Enumerate a normative standard syntax-role set in SPEC 18.4 parallel to the theme-role list (e.g. comment, string, keyword, function, constant, variable, type, number, operator, preprocessor, heading, link, todo, done, tag), state that unknown roles are ignored, and project that set into contract.json as `syntax_roles` so conformance tooling and both endpoints share one vocabulary.


### S7 · SPEC · 17.5 chart x-axis mapping (value-scaled vs ordinal) is undefined; the authored `x` is unused

SPEC SPEC 17.5


SPEC 17.5 requires "each ChartPoint MUST contain finite numeric `x` and `y`" but never states how `x` maps to a horizontal position. It gives no rule for whether the x-axis is value-scaled (screen position proportional to the point's `x`) or ordinal (points evenly spaced by array index), nor whether points must be sorted by `x`. W9 guessed ordinal: `xLine(i) = w * i / (n-1)` (VisualizationNodes.kt:135) plots points evenly by index and never reads the authored `x` at all. A value-scaling implementer would place them by `x`.


**Proposed resolution:** State in 17.5 whether the chart x-axis is value-scaled (position determined by `x`, sharing a common numeric axis across series) or purely ordinal (evenly spaced by index, `x` used only as an accessible label / tap payload), and whether a series' points MUST be strictly increasing in `x`.


### S8 · SPEC · 17.2 image: receiving an unadvertised-but-well-formed URI form — reject vs silently ignore — is undefined

SPEC SPEC 17.2


SPEC 17.2 imposes a sender gate — "Emacs MUST use only an advertised form" and the Companion "MUST advertise at least one of image.https or image.data" — but never states the receiver's duty when a snapshot arrives with a form that is well-formed yet not advertised (a data:image URL when only image.https is in `features`, or vice versa). Is that a whole-surface 1201 content-invalid reject (like 16.1 malformed content), or a per-node load failure that renders the placeholder? W9's SpecValidator (SpecValidator.kt:506-515) accepts either form purely on syntax via ImageGuards.isValidImageUrl, explicitly deferring the advertisement decision to "runtime" (comment lines 507-511), and no code path is shown that turns an unadvertised form into a reject — so the choice is unpinned and inconsistently placed.


**Proposed resolution:** State the receiver disposition for an unadvertised image form: either it is content-invalid and MUST reject the surface with 1201 (treating advertisement as a validation-layer rule), or it MUST be treated as a load failure and render `content_description`/placeholder. Name the layer (validate-time vs load-time) so implementers agree.


### S9 · SPEC · 18.4 SyntaxStyle member precedence vs a token's intrinsic styling is undefined; bg/weight/italic/underline are droppable

SPEC SPEC 18.4


SPEC 18.4 says "A SyntaxStyle MAY contain fg, bg, font_weight, italic, and underline" but never defines how those members compose with the Companion's own per-token rendering (e.g. it draws comments italic and keywords bold on its own — SyntaxHighlight.kt:185,219). There is no precedence rule: does a role's `font_weight:normal` override the Companion's intrinsic bold-keyword, or is the intrinsic style authoritative? W9 resolved this by reading ONLY `fg` and discarding bg/font_weight/italic/underline entirely (syntaxFg reads `fg` only, SyntaxHighlight.kt:78-86; comment: "bg/weight/italic/underline are the token's own per-type decisions"). Another implementer would honor all five, producing visibly different fontification for the identical theme.set.


**Proposed resolution:** Define precedence in 18.4: a SyntaxStyle's PRESENT members override the Companion's intrinsic styling for that role (fg, bg, weight, italic, underline each independently), and ABSENT members fall back to the Companion default. State whether receivers MAY ignore non-fg members (making them advisory) or MUST honor them.


### S10 · SPEC · 17.2 image: the supported media-type set and the meaning of "active or unsupported" are unnamed

SPEC SPEC 17.2


SPEC 17.2 for image.data says the Companion "MUST validate the media type and decoded bytes... and reject active or unsupported formats" but never names the supported raster set nor defines "active". SVG is clearly active/scriptable, but is animated GIF or APNG "active"? Is WebP/HEIC required or optional? W9 had to invent the set: SUPPORTED_MEDIA_TYPES = {png, jpeg, gif, webp, bmp, heic, heif}, excluding svg (ImageGuards.kt:17-19), and this same set is used to gate content validity at SpecValidator.kt:512. Emacs cannot know what a given Companion will decode, and two Companions will disagree (one accepts heic, one rejects bmp).


**Proposed resolution:** Name a minimum mandatory raster set for image.data (e.g. png, jpeg — plus webp), enumerate the excluded/active formats explicitly (svg and any format that can execute script or fetch external resources), and define "active" as a format capable of scripting, external references, or code execution. Optionally project the accepted set into contract.json.


### S11 · SPEC · 17.5 chart on_point_tap: which series' point, and behavior between/off points, is undefined

SPEC SPEC 17.5


SPEC 17.5 says "If on_point_tap is present, the Companion MUST return the complete authored point object in args.value" — singular "the point object" — but a chart may have multiple series of unequal length, and a tap rarely lands exactly on a vertex. The SPEC defines neither which series is consulted nor how a between-points or off-the-end tap resolves to a point. W9 guessed: it taps only the FIRST series (`s0 = series.firstOrNull()`, VisualizationNodes.kt:122) and snaps to the nearest index by proportional x (`((off.x/width)*(n-1)).roundToInt()`, line 124), ignoring every other series and the points' actual `x` values.


**Proposed resolution:** Specify point resolution: the Companion MUST return the nearest authored point (by rendered distance) across all series, or MUST return the nearest point of a named primary/first series; and state that a tap is always snapped to the closest authored point (there is no between-points null result). Clarify how unequal-length series are handled.


### S12 · SPEC · 18.5 chronometer: count_down semantics relative to base_ms (past-start vs future-target) is undefined

SPEC SPEC 18.5


SPEC 18.5 defines chronometer as only "{base_ms, count_down?}; base_ms is an epoch timestamp and count_down defaults to false" and says nothing about what count_down does relative to base_ms. Count-up conventionally shows elapsed time since a base in the PAST; count-down shows remaining time until a target in the FUTURE — the same field means opposite things and the SPEC never says which. W9 passes base_ms straight through to setWhen/setChronometerCountDown (Notifications.kt:169-174) without defining the invariant, so whether base_ms should be a past or future instant for count_down:true is left to Emacs's guess and the platform's interpretation.


**Proposed resolution:** Define the invariant in 18.5: count_down:false counts elapsed time forward from base_ms (base_ms SHOULD be in the past); count_down:true counts remaining time down to base_ms (base_ms SHOULD be in the future). State the display behavior when base_ms is on the wrong side of now.


### S13 · SPEC · 18.5 priority: whether `max` must be presented distinctly from `high` is unstated

SPEC SPEC 18.5


SPEC 18.5 lists priority as "min, low, default, high, or max" (five values) but never says whether `max` must be observably stronger than `high`, nor what any level obligates. Android's channel importance has no user-facing level above IMPORTANCE_HIGH, so W9 collapses both to the same channel importance: `"high", "max" -> IMPORTANCE_HIGH` (Notifications.kt:135). If the SPEC intends five distinguishable levels this is nonconformant; if four effective buckets are acceptable it is fine — but the SPEC gives no way to tell.


**Proposed resolution:** State in 18.5 whether `max` MUST be presented at least as prominently as `high` and MAY equal it (allowing platforms with only four effective levels to map max→high), or whether the five levels MUST be mutually distinguishable where the platform supports it. A one-sentence 'best-effort, monotonic, platforms MAY coalesce adjacent levels' rule suffices.


### S14 · SPEC · 17.7 line-start: "exact literal inserted prefix" no-op test vs the implemented trimmed comparison

SPEC SPEC 17.7


SPEC 17.7 says "`line-start` MUST no-op when the line already starts with the exact literal inserted prefix." "Exact literal" reads as an untrimmed, byte-for-byte start-of-line comparison, but that is awkward for the intended org-mode use (indented list/heading prefixes) and for prefixes that themselves carry leading whitespace. W9 quietly diverges to a trimmed comparison: `want = prefix.trimStart()` and `here.trimStart().startsWith(want)` (ToolbarEdits.kt:131-134), so a `"- "` prefix no-ops on an already-indented `"  - foo"` line — which the literal reading would NOT treat as already-present. The SPEC neither authorizes nor forbids the trim, and does not address a prefix with leading whitespace.


**Proposed resolution:** Clarify 17.7: state whether the already-present test compares the prefix against the line start ignoring leading whitespace (trimmed) or byte-for-byte (literal), and define behavior when the inserted prefix itself begins with whitespace. If trimming is intended for outline/list prefixes, say so explicitly and drop the word 'literal'.


---

## Plausible (unverified — needs a human call)


### SPEC · [spec-gaps] 17.5 canvas coordinate-space unit (dp vs px) and text `size` unit are not pinned
`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/VisualizationNodes.kt:191`

SPEC 17.5 says only "Coordinates are finite numbers in the canvas coordinate space" and lists the `text` op's `size` as an optional "finite number" — it never states the unit. 16.5 makes universal layout numbers dp "unless stated otherwise", but 17.5 deliberately introduces a distinct phrase, "the canvas coordinate space", which reads as its own (possibly px) unit and is never tied back to dp. W9 chose dp for everything, including text size: `fun px(v) = v.toFloat().dp.toPx()` (VisualizationNodes.kt:191) and `textSize = px(o.optDouble("size",12.0))` (line 235).
