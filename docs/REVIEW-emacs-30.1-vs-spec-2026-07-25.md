# REVIEW — EBP SPEC against Emacs 30.1 source (2026-07-25)

**Question asked:** what SPEC changes does the real Emacs source tell us we need?

**Method.** Twelve spec-area × Emacs-subsystem pairings, reviewed in parallel, each finding then
adversarially re-verified by an independent agent that re-opened the cited source and re-grepped the
spec before allowing the claim to stand. All Emacs citations are read at the **`emacs-30.1` tag**
(`git -C ~/pkb/resources/emacs/emacs show emacs-30.1:PATH`), not the master working tree; behavioral
claims were additionally reproduced on a live GNU Emacs 30.1. 43 candidate findings → **12 refuted,
31 survived** (12 CONFIRMED, 19 CORRECTED), merged into **21 amendment entries**.

**Version floor under test.** Emacs 30.1 on Android, dialing loopback TCP to the Companion, renting
core `jsonrpc.el` 1.0.25 + `src/json.c` — the configuration SPEC-CHANGES #34 and SPEC.md:466–467
explicitly bless.

---

## Executive summary

The headline is not a list of 21 unrelated defects. It is **one paragraph**: §6.2's delegation clause
(SPEC.md:462–470), which relaxes receiver obligations for the Emacs endpoint on the grounds that it
"MAY delegate framing and message decoding to a host-platform JSON-RPC library — such as core Emacs
`jsonrpc.el` — accepting that library's tolerances." **Thirteen of the 31 surviving findings trace
back to it.** The clause is unbounded along three axes it never intended to open:

1. **It says nothing about the delegate's *diagnostics*.** `jsonrpc.el` logs every raw frame body —
   including the §9.3 authentication proof and submitted password values — into a never-trimmed
   buffer, by default. That is a §23.3 MUST NOT violated by construction. (P1-1)
2. **It says nothing about resources the delegate commits *before validation*.** Wire-supplied member
   names and method names are interned into a process-lifetime table that is a GC root. Measured:
   +200,000 permanent symbols, RSS 56 MB → 221 MB, linear and unreclaimable. (P1-2)
3. **"Tolerances" cannot bear the weight of *non-termination*.** A tolerance is "I accepted something
   I could have rejected." A permanent silent stall is not that — and it is what `jsonrpc.el` does
   when a header section exceeds its 100-character scan bound. (P2-1)

**The single highest-leverage change** is therefore to bound that clause in three sentences (see
"The one change that matters most"). Every P1 and most P2 entries then become local elaborations of a
coherent rule rather than a scattering of patches. It costs one paragraph, no `contract.json` change,
and no golden change.

### The five P1s

| # | Finding | Why it is P1 |
|---|---|---|
| P1-1 | The blessed library writes the auth proof and every password verbatim into a persistent, never-trimmed buffer, by default | §23.3 MUST NOT, violated by construction; §24.6 item 12 unpassable today |
| P1-2 | Wire names interned into a GC-rooted, process-lifetime table before any validation | Unbounded permanent memory growth, pre-auth reachable; §23.5 names no such resource |
| P1-3 | §5.3's wake target on Android is an argv-injection channel | Spec constrains what the wake signal MUST NOT *contain*, never what it MUST NOT *cause* |
| P1-4 | §9.1's keystore MUST binds Emacs, which has no keystore API from Lisp; the escape hatch names only the Companion | Emacs endpoint non-conformant by construction |
| P1-5 | §19 never requires the synced document to be Unicode scalar values; Emacs chars are a strict superset | The natural defensive fix (1 char → U+FFFD) passes every length gate while silently corrupting the user's file |

### Caveat on P1-3, stated plainly

The argv exposure is a **pre-existing property of Emacs on Android**, not something EBP creates: any
app on the device can already start the exported `EmacsActivity` with startup arguments. The spec
change does not fix Emacs. What it does is stop a *conforming Companion* from being the vehicle, and
stop implementers from reading §5.3's "an exact application component" as sufficient. Verified
independently: `java/AndroidManifest.xml.in:226` (`android:exported="true"`),
`EmacsActivity.java:269` (`getStringArrayExtra` with no caller check), `EmacsThread.java:58-68`
(spliced verbatim into `EmacsNative.initEmacs`).

### On an Emacs version floor

Two dimensions raised it and reached opposite conclusions on different clauses; both are right.
**For:** §4.5's own carve-out (amendment #35) assumes "a host JSON-RPC library that bounds recursion
by its own means" — true only from Emacs 30 onward, because `json.o` is unconditional in
30.1's `src/Makefile.in` but gated behind `JSON_OBJ = @JSON_OBJ@` in 29.1's, and without the built-in,
`jsonrpc.el` silently degrades to `json.el`'s *recursive* `json-read`. That belongs in **§24.2**
(already the Emacs-specific conformance section, so it does not breach the implementation-agnostic
rule). **Against:** the feared crypto build-conditionality does not exist — `gnutls-hash-mac` is
`#ifdef HAVE_GNUTLS3` and GnuTLS is a packager add-on on Android, but `secure-hash` is unconditional
core and returns 32 raw octets under BINARY, so RFC 2104 HMAC-SHA-256 is constructible in pure Lisp on
every 30.1 build and §24.6's KAT is passable without GnuTLS. No floor language is warranted in §9.

### What is explicitly *not* a finding

Recorded so it is not re-litigated. `json.c` genuinely cannot detect duplicate member names for any
`:object-type` (no check exists at json.c:1486–1591) and genuinely cannot reject invalid UTF-8 — **but
§6.2:462–469 already scopes both asymmetrically**, so the spec handles them. Also clean: unpaired
surrogates *are* rejected (json.c:1161–1181), `NaN`/`Inf` *are* refused on serialize (json.c:514–515)
and on parse (json.c:1265–1268), raw control characters and trailing content are rejected, `-0.0` is
already covered by §4.3, and §5.3's wake language is correctly hedged against Android doze. Twelve
further candidates were refuted outright and are listed under "Dropped."

---


**Scope:** 12-dimension review, 31 surviving findings, all adversarially verified (12 CONFIRMED, 19 CORRECTED, 0 refuted-but-retained, 0 unverified). Merged below into **21 amendment entries**. Where a verifier issued a correction, the corrected claim, severity, and amendment text are what appear here; the original overstatements are recorded under "Dropped."

Version floor under test: **Emacs 30.1 on Android**, dialing loopback TCP to the Companion, renting core `jsonrpc.el` 1.0.25 + `src/json.c` (the configuration SPEC-CHANGES #34 and SPEC.md:466–467/499 explicitly bless).

---

## P1 — five entries

### P1-1. A delegated host JSON-RPC library writes the authentication proof and every password verbatim into a persistent, never-trimmed log — by default
**Dimensions converged: error-model + security-elisp-surface** (both CONFIRMED, both reproduced live on GNU Emacs 30.1).

- **Claim:** §23.3's MUST NOT ("authentication proofs, password values, … private editor content MUST NOT appear in normal logs, metrics, diagnostics, Goldens, or crash reports") is violated by construction on the exact library §6.2 blesses, because §6.2's delegation allowance covers decoding *strictness* and is silent about the delegate's *diagnostics*.
- **Sections touched:** §23.3 (SPEC.md:3528–3536), §6.2 (462–470), §8 (584–585), §24.6 item 12 (3698).
- **Emacs evidence:** `emacs-30.1:lisp/jsonrpc.el:79-80` declares `-events-buffer-config :initform '(:size nil :format full)`, `:983` installs `jsonrpc--log-event` on `jsonrpc-event-hook` by default, `:1020` gates on `(when (or (null max) (cl-plusp max))` — true when `:size nil` — and `:1043` formats `('full (format "%s%s\n" preamble (or json log-text)))`, inserted at `:1058` with the trim branch guarded `(when max …)`, i.e. never; both directions are logged (`:586` outbound, `:241`/`:258` inbound), and `:768-769` additionally pushes the raw body of any undecodable frame through `display-warning`.
- **Live reproduction:** `*ebp-t events*` contained `--> auth.response {"jsonrpc":"2.0",…,"client_proof":"deadbeef…"}` and `<-- event.action {…"fields":{"password":"hunter2"}}`.
- **Why it matters beyond the proof:** §14.6 requires the Companion to erase every locally controlled copy of a submitted password while the receiving Emacs retains it in plaintext for the process lifetime; §24.6 item 12 ("password-state exclusion from persistence and logs") is therefore unpassable on the Emacs endpoint today.
- **Proposed amendment** (§23.3, new paragraph after L3536; shape 5 + shape 4):

  > Section 6.2's delegation allowance does not extend to a host library's diagnostics. Where an endpoint delegates framing, decoding, or message dispatch to a host JSON-RPC library, it MUST, before the first frame is exchanged on a connection, disable or redact every facility of that library that records raw frame bodies, decode failures, or message payloads, so that no value named in this section is written to any log, trace buffer, warning, or diagnostic sink. An endpoint MUST NOT assume such a facility is disabled by default, and MUST NOT enable it for a connection carrying a value named in this section. Where such logging is retained under the explicit developer setting above, it MUST be bounded in size and lifetime.

  *Informative note* (names Emacs only here): core `jsonrpc.el` 1.0.25 defaults `-events-buffer-config` to `(:size nil :format full)` and `jsonrpc-event-hook` to `(jsonrpc--log-event)`; constructing the connection with `:events-buffer-config '(:size 0)` and removing the hook satisfies the rule. Add a cross-reference at §8 L585.
- **Artifacts:** no golden or contract.json change. §24.6 item 12 should be widened to "password-state **and authentication-proof** exclusion from persistence, logs, warnings, and any delegated host-library message trace."

---

### P1-2. Wire-supplied member and method names are interned into a process-lifetime table before any validation runs; §23.5 names no such resource, and §12 rule 1 mandates the tolerance that keeps the stream alive
**Dimensions converged: security-elisp-surface (CONFIRMED, P1) + jsonrpc-conventions (S7, P2, method-name grammar/bound).**

- **Claim:** §23.5's bounded-resource enumeration is entirely per-object; nothing bounds the *union of distinct names across frames*. On the blessed path the allocation is permanent, cross-session, and happens inside the decoder, before §7.3/§11 can refuse anything. Separately, §4.5 bounds every other unbounded wire string (identifier 128 octets, request ID 64) but places **no bound and no grammar** on `method`.
- **Sections touched:** §23.5 (3556–3562), §12 rule 1 (1006–1007), §7.3 (512–513), §4.5 limits table (186–195), §11 (953–958).
- **Emacs evidence:** `emacs-30.1:src/json.c:1523`/`:1532` pass `intern = true` to `json_parse_string` for the alist and plist object arms (hash-table arm at `:1512` passes `false`), and `json.c:1090-1091` returns `intern_c_multibyte (…)`; `src/lread.c:4985` interns into `check_obarray (Vobarray)`, a GC root (`src/alloc.c:7330-7335`, `case PVEC_OBARRAY: … mark_stack_push_values`), so entries are never collected. `lisp/jsonrpc.el:632` hard-codes `:object-type 'plist`, and `:305`/`:320` apply `(intern method)` *inside the dispatcher call's argument list*, before any endpoint check including the session-state check.
- **Measured on GNU Emacs 30.1:** `mapatoms` 18,208 → 38,208 after 20,000 plist objects (survives `garbage-collect`), → 58,206 with `'alist`, **+0** with `'hash-table`. Four 3.28 MB bodies of 260,000 distinct names each: RSS 56 MB → 221 MB, permanent and linear; hash-table decoding plateaus.
- **Reachability:** §23.6 concedes loopback does not authenticate a local process and Emacs is the dialer, so a local app winning the connect race drives this pre-auth; §12 rule 1 and §7.3 *require* the endpoint to keep reading.
- **Proposed amendment** (three parts):
  1. §23.5, new paragraph after L3562, implementation-agnostic (interning pools exist in Java, Python, Ruby, Lua, Elisp):
     > Decoding MUST NOT let a peer's choice of names grow an unbounded process-lifetime table. Where a receiver's decoder maps wire-supplied member names, method names, or enum values into a process-global interning pool, symbol table, or equivalent structure whose entries are not reclaimed when the message, session, or connection ends, the receiver MUST select a decoding mode that does not intern peer-supplied names, or MUST bound and reclaim that pool. This obligation is not satisfied by rejecting the unknown name after decoding: the allocation occurs first. It applies to names the receiver is required to tolerate under Section 12 rule 1 and to names it rejects under Section 7.3. **This obligation is not relaxed by Section 6.2**: the cost is permanent and cross-session, not per-frame.
  2. §4.5 limits table, new row: `| Method name | 128 UTF-8 octets and the Section 4.4 ASCII grammar |`; §11 after L956: "A method name MUST be a Section 4.4 identifier. A receiver MUST reject a request whose method name is not a Section 4.4 identifier with `-32601`, and MUST log and ignore such a notification, without consulting the registry."
  3. §7.3 after L512: "A receiver MUST NOT allocate unbounded or non-reclaimable state keyed by an unvalidated method name; method-name validation MUST precede any such allocation."
  - *Informative:* `json-parse-*` interns member names for `:object-type` `plist`/`alist` and not for `hash-table`; `jsonrpc.el` hard-codes `plist` and additionally `intern`s the method name pre-dispatch.
- **Artifacts:** contract.json — add `limits.fixed.max_method_bytes: 128`. §24.6 — extend item 4 with "an over-long and a non-identifier method name," and add "a frame carrying many distinct unknown member names, and a run of distinct unknown method names, verified not to cause unbounded process-lifetime growth." A golden can carry the frames but **not** the assertion (it is a memory property).

---

### P1-3. §5.3's wake target on Emacs 30.1/Android is an argv-injection channel: the spec constrains what the wake signal MUST NOT *contain*, never what it MUST NOT be able to *cause*
**Dimension: device-capability-triggers (CONFIRMED).**

- **Claim:** §5.3 forbids the harmless routes (implicit broadcast, URI handler, shell, network) and mandates "an exact application component," which on the target platform resolves to exactly one reachable thing — and then constrains only the signal's confidentiality, never its authority.
- **Sections touched:** §5.3 (356–371, decisive 359–363), §21.1 `wake` row (3030), §3 invariant (100–102).
- **Emacs evidence:** `emacs-30.1:java/AndroidManifest.xml.in` makes `EmacsService` and the CancellationReceiver `android:exported="false"` and gates the DocumentsProvider on `MANAGE_DOCUMENTS`, leaving `EmacsActivity` (`android:exported="true"`, MAIN/LAUNCHER) as the only peer-reachable component; `EmacsActivity.java:95` defines `EXTRA_STARTUP_ARGUMENTS = "org.gnu.emacs.STARTUP_ARGUMENTS"` and `:267-269` in `onCreate` does `intent.getStringArrayExtra (EXTRA_STARTUP_ARGUMENTS)` **with no caller check**; `EmacsThread.java:58-68` splices that array straight into `args` and calls `EmacsNative.initEmacs (args, …)`.
- **Consequence:** a §5.3-conformant Companion may attach `{"--eval","…"}` or `{"-l","/sdcard/x.el"}` to the wake intent — arbitrary code execution in the endpoint holding the pairing token, before any authentication. `onNewIntent` (574–592) ignores everything but Emacs's own notification tag, so argv is the *only* route that does anything, and only in the cold-start case, i.e. exactly the wake case.
- **Verifier caveat (does not change the claim or fix):** `EmacsThread` has an explicit `extraStartupArguments == null` branch, so a bare component start with **no extras** cold-starts Emacs fine — which makes the inertness requirement strictly *more* achievable.
- **Proposed amendment** (§5.3, after L363; shape 5):
  > The wake signal is an authorization-bearing message to the Emacs host and MUST be inert. Its payload MUST be limited to the non-secret pairing ID and MUST NOT carry, or be able to be interpreted by the target as, startup arguments, a command line, code to evaluate, a file or library to load, an initialization file, an environment override, or any other parameter that influences how the Emacs host initializes or what it executes. A Companion MUST reject a user-configured wake target that requires such a parameter to function, and MUST re-verify inertness of the exact signal immediately before each send, alongside the target re-check already required at SPEC.md:373–376.

  *Informative:* on at least one target platform the only externally reachable component of an Emacs host is its launcher activity, whose accepted extras include a startup-argument array spliced directly into the host's command line; implementers must send the component start with no extras at all. Cross-reference from §21.1's `wake` row.
- **Artifacts:** none (prose only; no wake projection in contract.json, no golden).

---

### P1-4. §9.1's keystore MUST binds both endpoints; Emacs 30.1 exposes no keystore from Lisp, and the "no such facility" escape hatch names only the Companion
**Dimension: pairing-crypto (CONFIRMED).**

- **Claim:** §9.1 L610–613's "Where a platform provides keystore-backed encrypted storage, the pairing token and any recoverable HMAC key material MUST use it" has no subject restriction, both endpoints store the token (L604–606), and Android *does* provide the facility — so the Emacs endpoint is non-conformant by construction, while the only relief sentence (L615–617) says "A **Companion** on a platform with no such facility."
- **Sections touched:** §9.1 (609–617); cross-referenced by §21.5 and §23.3.
- **Emacs evidence:** `git grep -l -iE 'keystore|KeyGenParameterSpec|EncryptedSharedPreferences|javax\.crypto' emacs-30.1 -- java/ src/ lisp/` returns only `java/INSTALL`, `java/Makefile.in`, `java/README`, all referring to `emacs.keystore`, the APK **signing** key; the complete Android DEFUN surface (androidfns.c / androidselect.c / androidmenu.c / androidterm.c) is frames, colors, geometry, battery, clipboard, notifications, storage-access — no cipher, no keystore.
- **Aggravating facts:** `java/AndroidManifest.xml.in:314-319` exports `EmacsDocumentsProvider` over Emacs's home directory (`doc/emacs/android.texi:1163`) — reachable via the system picker (though `android:permission="android.permission.MANAGE_DOCUMENTS"` means the user must pick the file, weakening but not removing this) — and `java/INSTALL:222-230` documents `--with-shared-user-id=com.termux`, under which "storage private to each endpoint" is simply false.
- **Proposed amendment** (§9.1, replace L610–617; shape 1 + shape 5):
  > Where the platform provides keystore-backed encrypted storage, the Companion MUST hold the pairing token and any recoverable HMAC key material under it, on the same unconditional terms as Section 21.5's sensitive queued data, and MUST NOT hold them in plaintext application storage weaker than the protection Section 23.3 requires for the SMS and call data the token's authority can reach. An endpoint whose platform provides such a facility but exposes no interface to it from the endpoint's implementation environment, and an endpoint on a platform with no such facility, MUST instead meet the following floor: the token MUST be written only to storage the platform reserves to that endpoint's own application identity, with the most restrictive access mode the platform offers; it MUST NOT be written to storage shared with another application identity, to user-visible or externally browsable storage, or to any location the endpoint exports to other applications; and the endpoint MUST make the reduced protection explicit to the user at pairing time. An endpoint that cannot meet that floor MUST NOT persist the pairing and MUST require re-pairing each session.

  *Informative:* an endpoint's nominally private directory may be browsable through a system document-provider or shared outright under a common platform user identity; keep the token outside any exported subtree or treat the floor as unmet.
- **Artifacts:** none. SPEC-CHANGES row required (this revises amendment #78, whose rationale was entirely Companion-side).

---

### P1-5. §19 never requires the synchronized document to be representable as Unicode scalar values; the natural defensive fix is silent, undetectable user-data destruction
**Dimension: editor-sync-positions (CORRECTED — scope narrowed by §4.1, severity held at P1).**

- **Claim:** §19's only presentation precondition is the `max_editor_bytes` size test (L2551–2554). Nothing makes a document whose text is not a sequence of Unicode scalar values *ineligible*, nothing forbids the sender substituting a representable character, and §19.4 defines no typed outcome.
- **Sections touched:** §19 preamble (2551–2562), §19.1 (2590–2594), §19.3 length gate (2673).
- **Emacs evidence:** `emacs-30.1:doc/lispref/nonascii.texi` — "Emacs character codes are a superset of the Unicode standard… values `#x3FFF80` through `#x3FFFFF` represent eight-bit raw bytes"; `src/character.h:53/:60/:106-113` (`MAX_UNICODE_CHAR`, `CHAR_BYTE8_P`, `BYTE8_TO_CHAR`). Emission is impossible rather than lossy: `src/json.c:302` `string_not_unicode` → `wrong_type_argument (Qjson_value_p, obj)`, guarded at `:347/:355/:365/:369/:375` inside `json_out_string` (`:322`).
- **Why P1:** §4.1 (118–123) already bars ill-formed Unicode on the wire, so branch (c) "emit the raw byte" is closed. The live path is branch (b): a defensive 1 char → 1 U+FFFD substitution **preserves scalar length**, so every §19.3 length gate (`len = old_length - del + scalar_length(text)`, L2673) keeps passing while shadow and buffer differ — and the first Companion splice covering that position writes U+FFFD into the user's file. One stray undecodable byte in an org file on Android is enough. Branch (a) (serializer signals) has no defined `data.reason` and no state transition.
- **Proposed amendment** (§19 preamble, after L2554, same asymmetric shape as the `max_editor_bytes` sentence):
  > Emacs MUST NOT present a synchronized `editor` whose document text is not a sequence of Unicode scalar values. An endpoint MUST NOT substitute, drop, or replace any character in order to make a document, an `edit.apply` splice, an `edit.delta`, or an `edit.resync` result representable; a document that cannot be represented losslessly is not eligible for synchronization. If an authoritative document acquires such text while a session is open, Emacs MUST withdraw the synchronized `editor` using the mechanism already named at L2557–2562 (node removal, tombstoning, document change, or presentation-identity change) rather than emit a lossy splice.

  *Informative:* some host text models admit single text positions that are not scalar values — undecodable raw bytes retained verbatim, code points not unified with Unicode, unpaired surrogates. Such a position is one position but zero scalar values, so Section 19.1's arithmetic does not apply; a 1:1 replacement character keeps every Section 19.3 length check passing while the two texts silently differ.
- **Artifacts:** contract.json unaffected. `frames.golden` carries only ASCII editor rows (14–16, 30–34); add one `edit.delta` row whose `text` contains an astral character with `start`/`del`/`len` in scalar values — it catches a UTF-16-counting Companion and is the natural place to assert non-scalar content never appears.

---

## P2 — eleven entries

### P2-1. Framing: an 8,192-octet header floor the blessed receiver cannot reach, and a failure mode that is a permanent silent stall rather than a close
**Dimensions converged: framing-transport + conformance-goldens + security-elisp-surface + error-model** (four dimensions; the stall was independently rediscovered three times).

- **Claim:** §4.5:190 publishes an 8,192-octet header section inside a table §4.5:197 makes a MUST-accept; the blessed receiver's real budget is **100 characters**, and over-budget or unparsable header sections produce neither a close nor a diagnostic but an unbounded, permanent wedge — which independently violates §22.3:3451-3453 ("MUST apply transport backpressure before unbounded memory growth"). §6.2's "accepting that library's tolerances" is written broadly enough to appear to bless non-termination, which is not a tolerance.
- **Sections touched:** §4.5 (190, 197–199), §6.1 (393–395), §6.2 (404–415, 449–453, 462–470), §22.3 (3451–3453), §23.5 (3558–3559), §24.6 item 3 (3682–3685).
- **Emacs evidence:** `emacs-30.1:lisp/jsonrpc.el:740-744` is the entire header parser — `(search-forward-regexp "\\(?:.*: .*\r\n\\)*Content-Length: *\\([[:digit:]]+\\)\r\n\\(?:.*: .*\r\n\\)*\r\n" (+ (point) 100) t)` — and `:745-746` handles a non-match with `(setq done :waiting-for-new-message)`: no close, no error, no log; `delete-region` fires only on the completed-message branch (`:781-783`), so the prefix is retained and every later octet re-runs the same failing search. `src/search.c:1060` merely clamps the bound rather than erroring. Separately, `jsonrpc.el:745` records the declared `Content-Length` with **no upper bound** and `:754` waits on `(>= available-bytes expected-bytes)`, so `Content-Length: 999999999` plus a slow dribble grows the process buffer without limit and never completes a frame.
- **Measured on GNU Emacs 30.1 over loopback TCP:** an 80-octet two-field header section is accepted; a 111/129-octet three-field section returns nil and leaves the frame in the buffer forever with the connection alive and nothing logged. Also measured against the repository's own fixtures: `12-duplicate-length.bin` is **accepted** (returns 2; differing values last-wins), `14-signed-length.bin` and `11-missing-length.bin` both **stall** — where `manifest.json` expects `close` for all three.
- **Proposed amendment** (three edits):
  1. §4.5, after L198 (shape 1 — scope): "The header-section figure above is a receiver **rejection threshold**, not a sender allowance. A sender MUST NOT rely on a peer accepting a header section longer than 128 octets. Acceptance of a header section carrying fields other than `Content-Length` up to that floor is REQUIRED for the Companion and RECOMMENDED for the Emacs endpoint, which MAY delegate framing to a host JSON-RPC library whose header scan is bounded well below 8,192 octets."
  2. §6.1 L395 (shape 3): replace "It SHOULD NOT emit any additional header field." with "Under the `android-loopback-tcp` profile a sender MUST NOT emit any header field other than `Content-Length`; the header section is therefore exactly `Content-Length: <decimal-octet-count>\r\n\r\n`. A future transport profile that permits additional header fields MUST define their syntax, including whether whitespace after the colon is required, and MUST state the header-section budget an endpoint may rely on."
  3. **The bounded-terminal-reaction rule, REQUIRED for both roles** (§6.2, appended to the paragraph ending L453 — this is the same edit S31 and S27 arrived at independently): "A receiver MUST reach a terminal outcome once it has buffered a header-section prefix it cannot classify up to the 8,192-octet cap, and MUST NOT accumulate more unparsed octets for a single incomplete frame than `max_frame_bytes` plus the Section 4.5 header allowance, whether the excess is declared in the header section or arrives as a body that never completes. A role excused by this section from a strictness obligation still owes a bounded reaction: it MUST NOT accept the vector as a valid message, and it MUST reach close, discard, or a documented tolerance within Section 22.3's bounds. An unbounded stall is not a conforming alternative to the closes required above and is a conformance failure for every role." Add the §6.2 cross-reference to §23.5's first sentence (which today restates the Section 4 limits as an unqualified MUST, contradicting §6.2 — §4.5:209-212 already shows the house form for this).
  - *Informative:* §4.5's header cap is a ceiling a receiver must not exceed, not a budget a sender may spend; host libraries commonly parse the header section with a single bounded pattern match (core `jsonrpc.el` 1.0.25 bounds it to 100 characters) and fail by waiting indefinitely rather than by closing. This is implementable without patching the library — a wrapping process filter or a `process-buffer` size guard suffices — so it can be a MUST for both roles.
- **Artifacts:** contract.json — `limits.fixed` gains `max_send_header_bytes: 128` beside the existing 8,192 receiver figure. goldens — add a positive fixture with one ignorable extra field (~80 octets, inside the reachable range) and a negative `unterminated-header` fixture (>8,192 octets, no `\r\n\r\n`, `expect_error: close`); `validate.py`'s `decode_stream` currently only checks `len(head)+4 > MAX_HEADER` **after** finding `\r\n\r\n`, so an unterminated header section loops in the fill-until loop and is never rejected. §24.6 item 3 gains both.
- **Dropped from the original framing finding:** the claim that `X-Foo:bar\r\n` (no space after colon) wedges the receiver — `search-forward-regexp` is an unanchored *search* and simply skips the malformed field; verified delivering normally.

---

### P2-2. `json-serialize` caps emission at 50 containers while §4.5 publishes 64, the spec states no sender-side depth rule at all, and the resulting failure leaves a request permanently unanswered
**Dimensions converged: json-model + surfaces-actions-state + conformance-goldens** (three dimensions; severities after correction P2/P2/P3).

- **Claim:** §4.5's 64-container figure is a *receiver acceptance* bound and the spec never bounds a sender or defines what a sender does when it cannot encode a legal body. The 64-container budget is also the **only** depth budget §16.1 gives a node tree, and the reachable slice of it is roughly a third short.
- **Sections touched:** §4.5 (192, 197–200), §16.1 (1738–1739), §7.1 (480–483).
- **Emacs evidence:** `emacs-30.1:src/json.c:566` — `jo->maxdepth = 50;` in `json_serialize`, enforced by `json_out_nest` (`:404-408`, `--jo->maxdepth; if (jo->maxdepth < 0) error ("Maximum JSON serialization depth exceeded");`) once per container from `json_out_object_cons`/`_hash`/`_array`; `json_parse_args` (`:98`) accepts only `:null-object`/`:false-object`, so there is no override, and the parser is asymmetric at `:767` (`available_depth = 10000`). Still 50 on master, so no post-30.1 escape.
- **Measured:** 24 total nodes serialize, 25 signal. With a 2-container envelope and 2 containers per node level, §4.5 licenses ~30 node levels; Emacs delivers 24 (23 with a §13.4 `widget:*`/`notification:*` wrapper, 22 with a multi-view `app:*` spec).
- **The unanswered-request half:** in `emacs-30.1:lisp/jsonrpc.el`, the `condition-case-unless-debug` opened at `:303` wraps only the dispatcher; `(apply #'jsonrpc--reply conn id method reply)` at `:317` sits **outside** it, and `jsonrpc-connection-send` encodes at `:573` before `process-send-string` at `:579`. A depth error during reply encoding therefore escapes with no frame emitted, no connection close, and the peer's request never answered — violating §7.1:480.
- **Proposed amendment** (three parts):
  1. §7.1, after L483 (shape 3): "A responder that computes a result but cannot serialize the response body MUST answer the request with `-32603 internal-error`; it MUST NOT leave the request unanswered."
  2. §4.5, after L198 (shape 3 + shape 4): "Section 4.5's limits are receiver acceptance bounds. They do not license a sender to construct a message its own encoder cannot emit. A sender that cannot serialize a message MUST fail the attempt locally, MUST NOT emit a truncated or partial frame, and SHOULD report the fault as a local diagnostic." *Informative:* host JSON encoders impose serialization-depth caps independent of and lower than receiver acceptance limits — at least one in wide use caps at 50 containers, about 25 levels of container nesting, with no runtime override; a generator mapping deep document structure onto nested container nodes should flatten or paginate rather than rely on the receiver limit.
  3. §4.5 limits table, new row: `| Node nesting depth in one surface, dialog, or notification document | 20 levels |`, and §16.1 L1739: "…MUST fit the resource limits in Section 4.5. A document whose node nesting exceeds that depth MUST be rejected with `1201 content-invalid` and `data.reason: \"node-depth\"`."
- **Artifacts:** contract.json — `limits.fixed.max_node_depth: 20`, and `node-depth` added to the `1201` reason vocabulary. goldens — add a **positive** wire fixture at or near maximum nesting (today nothing exercises the boundary: `21-deep-nesting.bin` is negative-only, so an encoder that can reach only 50 passes every wire golden), plus a widgets golden at 21 node levels expecting `1201`/`node-depth`; `validate.py` needs a node-depth walk (its amendment-#35 pre-parse scan is body-level only). §25 classification: restricting a previously valid message.
- **Needs a human decision:** the constant **20** is a design choice, not an evidence-derived number (2 envelope + 2×20 + leaf + wrapper = 44 ≤ 50 leaves margin). The verifier disputed the original 48-container sender cap as hard-coding an Emacs constant into agnostic text; the informative-note form above avoids that, but the table row does pick a number.

---

### P2-3. Requester abandonment is undefined: the blessed library abandons every request at 10 seconds, sends nothing, and discards the late answer — including a submitted password — and §10.3's replay barrier has no failure cell
**Dimensions converged: jsonrpc-conventions + error-model + lifecycle-timers** (three dimensions; the third found the same root cause on the `queue.replay` path).

- **Claim (a), general:** §7.5 makes `rpc.cancel` a MAY; §7.2's "concluded" (the precondition for ID reuse) is undefined for local abandonment; §18.1's completion list is normatively exhaustive and contains no entry for requester silence. So a requester may walk away from a request the responder is obliged to keep outstanding forever.
- **Claim (b), specific:** §10.3 step 4 ("call `queue.replay` and wait for it to conclude") defines "conclude" only for a replay that *returns* with `remaining > 0` (L903–906). A replay that concludes with a JSON-RPC error (`1600 queue-busy` per L1675-1676, `1301` per L545), or that the caller abandons, has no defined outcome, and no deadline in the document bounds a stalled `SYNCING` (L788-789 is scoped to "an incomplete handshake"; L962 puts `session.ready` in `SYNCING`).
- **Sections touched:** §7.1 (480–483), §7.2 (496–498), §7.5 (537–549), §10.3 (900–908), §15.3 (1675–1676, 1686–1691), §18.1 (2302–2318), §20.2 (2880–2886), §4.5 (226).
- **Emacs evidence:** `emacs-30.1:lisp/jsonrpc.el:474-479` — `(defcustom jsonrpc-default-request-timeout 10 … :version "30.1")`, inherited by every request at `:870`; the expiry timer at `:889-897` runs `(jsonrpc--remove connection id …)` and an internal log and **writes nothing to the peer**; the eventual real response is dropped at `:270-283` with `"Response to request %s which has been canceled"`, followed verbatim by the author's own `;; TODO: … this seems to be also where notifying the server of the cancellation would come in.` Note `jsonrpc-request` splices the key conditionally (`:386`, `:432-433`), so `:timeout nil` does **not** disable it — only `:timeout <n>` or let-binding the defcustom does.
- **Failing case:** `dialog.show` with a password `text_input` in `capture_fields`. t=10 s: continuation deleted, nothing sent, dialog still modal. t=25 s: user submits; the Companion serializes the password into `fields` (§18.1 L2316-2318) and erases its live copy (§14.6 L1590-1595); Emacs drops the response. Credential transmitted, erased at the source, discarded at the destination. On the replay path: 300 queued events × one round trip each (§15.3 L1686-1691) against a 256-record floor (§4.5:226) exceeds 10 s trivially, and the session may never leave `SYNCING`.
- **Proposed amendment** (four edits):
  1. §7.1, after L481: "EBP defines no protocol-level request deadline. Where a method's registry section states that the responder keeps the request outstanding pending user interaction — `dialog.show` (Section 18.1) and `capability.invoke` (Section 20.2) — a requester MUST NOT apply a local deadline shorter than 60 seconds and SHOULD apply none. A requester that stops waiting for an outstanding request MUST send `rpc.cancel` for that ID before treating it as concluded, **except where another section requires it to close the transport without appending a frame (Section 14.6, SPEC.md:1600-1603)**; it MUST ignore any response later received for that ID, and MUST NOT reuse the ID for the remaining life of the connection. For the purposes of Section 7.2, a request has concluded only when its response has been received, its `rpc.cancel` has been sent, or the connection has closed. A response arriving for an abandoned request MUST be discarded without effect and is not a protocol fault."
  2. §7.5 L539: "…either endpoint MAY send `rpc.cancel` for an outstanding request it originated, and MUST send it when it abandons that request locally (Section 7.1)."
  3. §18.1, after L2314: "Requester silence is not a completion. `dialog.show` has no bounded latency and a requester SHOULD NOT impose a fixed local response deadline on it. Concluding a dialog under any of the three conditions above releases its `dialog_id`, which MAY then be reused."
  4. §10.3, replace L903–906: "A replay concludes for purposes of this barrier when it returns any result, when it returns any JSON-RPC error, or when Emacs abandons the wait under a finite local deadline. In every such case Emacs MUST proceed to `session.ready`, MUST preserve the backlog's FIFO priority, MUST NOT issue a second `queue.replay` before entering `READY`, and SHOULD retry replay in `READY` as required by Section 15.3." Plus, after §15.3 L1676: "A replay may make one round trip per retained event, up to `max_queued_events`; this document places no upper bound on its duration."
  - *Informative:* host JSON-RPC libraries commonly impose a fixed default per-request deadline (as little as 10 seconds) and send nothing to the peer on expiry; an endpoint must raise or disable it for user-paced and unbounded-duration methods and wire its expiry handler to emit `rpc.cancel`.
- **Artifacts:** contract.json — optional `user_paced: true` on the `dialog.show` and `capability.invoke` rows so the 60-second floor is machine-checkable (mirrors how §11's sender/class/state columns are already projected). §24.6 — add "requester abandonment of a user-paced request: assert `rpc.cancel` is sent, the responder concludes the original with `1301`, and the freed `dialog_id` is immediately reusable," and "a `queue.replay` that does not conclude before the caller's local deadline: assert the session still reaches `READY` and the backlog retains FIFO order."
- **Dropped:** "the `dialog_id` is permanently unusable for the life of the connection" — §18.1's `1201` fires only against a second *outstanding* request with the same ID, and the user's eventual submit concludes the first. Also dropped: "non-disableable" (refuted — `:timeout <n>` works) and "retries collect `1600` forever" (the Companion's replay concludes on its own; retries make progress).

---

### P2-4. Octet-transparency: the blessed receiver counts *decoded internal bytes*, under-consumes any body containing invalid UTF-8, then forward-scans the residue for a header — frame injection, verified end to end
**Dimension: framing-transport (CORRECTED; severity lowered P1 → P2, mechanism reproduced).**

- **Claim:** §6.2:448-451's two anti-injection rules ("The receiver MUST read exactly the declared number of body octets… MUST NOT attempt to resynchronize by scanning arbitrary body bytes") are broken by construction on the delegation path, and the spec never states the property they presuppose: that body accounting is in *transmitted octets*.
- **Sections touched:** §6.1 (after 400), §6.2 (448–451, 462–469), §4.1 (118–120).
- **Emacs evidence:** `emacs-30.1:src/coding.c` `decode_coding_utf_8` — `invalid_code: … *charbuf++ = ASCII_CHAR_P (c) ? c : BYTE8_TO_CHAR (c);` — never errors, mapping each malformed octet to a raw eight-bit character; `src/character.h:113` `BYTE8_TO_CHAR (byte) { return byte + 0x3FFF00; }` and `:259-263` `BYTE8_STRING` writes **two** internal octets. `lisp/jsonrpc.el:751-758` measures the body with `position-bytes`/`byte-to-position`, i.e. in internal bytes, so a body with *k* invalid octets is under-consumed by exactly *k*; `jsonrpc.el:740`'s `search-forward-regexp` is an unanchored forward scan that then finds a `Content-Length` line inside the residue.
- **Reproduced on Emacs 30.1 over loopback TCP:** a single declared 162-octet frame whose body is 76 × 0xFF + padding + a complete attacker-authored 76-octet frame delivered `GOT NOTIF INJECTED (:x 1)` — a frame the peer never framed.
- **Why P2 not P1:** §5.2's Section 9 mutual-HMAC floor means a pre-auth squatter's injected frames are refused anyway and a post-auth injector is the authenticated Companion. The harm is a by-construction MUST violation plus a permanent desync primitive, not a privilege gain.
- **Proposed amendment** (respecting amendment #34 — do **not** promote the rules to REQUIRED for Emacs):
  - §6.1, one sentence after L400: "A receiver counts and consumes body octets as transmitted; a length taken after any decoding step is not `Content-Length`."
  - §6.2, condition the delegation rather than leaving it unconditional: "An endpoint delegating framing to a host JSON-RPC library SHOULD ensure the library's body accounting is octet-identical to the wire for arbitrary octets, and SHOULD close rather than continue when a frame's declared and consumed octet counts disagree; it MUST NOT locate a header section anywhere other than immediately after a fully consumed preceding frame."
  - *Informative:* a host decoder that maps malformed input to substitute characters rather than failing can make a decoded body wider than the octets that produced it; a length check in decoded units then under-consumes the frame, and a header search implemented as a forward scan will find an attacker-authored `Content-Length` line in the residue. An implementation renting such a library can restore octet identity **without modifying it** by opening the connection in a binary coding system and holding its accumulation buffer unibyte — verified: with `(set-process-coding-system proc 'binary 'binary)` plus `(set-buffer-multibyte nil)` on the process buffer, the identical payload consumes all 162 octets as one frame and delivers no injected notification.
- **Artifacts:** goldens — add `22-body-embedded-header.bin`: one frame whose declared body is *k* invalid octets followed by a complete inner frame occupying exactly the last *k* octets, `kind: negative`, `expect_error: close` (or `parse-error` with **zero** trailing messages, so no decoder passes by synthesizing the inner frame). Add the vector to §24.6 alongside the existing invalid-UTF-8 item. No contract.json change.

---

### P2-5. §6.2's disclaimer names only §6.1, so §7.1's `params: {}` / `result: {}` and §4.1's absent-vs-`null` rule fall on the wrong side of the delegation line
**Dimension: json-model (two findings, S2 P2 + S3 P3, same edit site).**

- **Claim:** SPEC.md:468 reads "No sender obligation in **Section 6.1** is relaxed by this paragraph," inviting the *expressio unius* reading that obligations outside §6.1 are relaxed for a delegating endpoint. The blessed library lands exactly on the relaxed side in both directions.
- **Sections touched:** §6.2 (462–469), §7.1 (482–483, 488–489), §4.1 (131–134); consumers at §9:913 and §15:1675.
- **Emacs evidence (send):** `emacs-30.1:lisp/jsonrpc.el:643-648` calls `(json-serialize object :false-object :json-false :null-object nil)`; `src/json.c`'s `json_out_something` tests `EQ (obj, jo->conf.null_object)` **before** `NILP (obj)`, so `nil` emits `null` and the `"{}"` branch is dead. `jsonrpc-connection-send` splices `:params params` unconditionally, so `(jsonrpc-notify conn 'session.ready nil)` puts `"params":null` on the wire — contradicting `goldens/wire/04-empty-params.bin`, which is byte-for-byte `…"method":"session.ready","params":{}}`. The requirement **is** satisfiable without patching: an empty hash table hits `json_out_object_hash` and emits `{}`.
- **Emacs evidence (receive):** `jsonrpc.el:629-634` uses `(json-parse-buffer :object-type 'plist :null-object nil …)`; JSON `null` returns `parser->conf.null_object` = nil, an empty object returns nil (`json_parse_object` initialises `result = Qnil` and guards on `c != '}'`), and an absent member is nil via `plist-get` — a three-way collapse of exactly the distinction §4.1:131-134 asserts. No member defined today depends on it in the Companion→Emacs direction (`blocked_by` collapses harmlessly; §18.4's `colors`/`syntax` are Emacs-sent), so this half is a **forward-compatibility** constraint, not a live divergence.
- **Proposed amendment:**
  1. §6.2 L468 (shape 1): "No sender obligation **in this document** is relaxed by this paragraph; in particular Section 7.1's `params: {}` and `result: {}` requirements bind an endpoint that delegates framing and decoding to a host library."
  2. §6.2 L462–463: extend the carve-out to name "Section 4.1's absent-versus-`null` distinction and no-coercion rule" alongside the duplicate-member and encoding rejections, keeping them REQUIRED for the Companion and RECOMMENDED for the Emacs endpoint.
  3. §4.1, after L134 (shape 3): "A member sent toward an endpoint permitted that relaxation MUST NOT assign different EBP meanings to its absence and to an explicit `null`. A member definition that distinguishes the two is permitted only in the Emacs-to-Companion direction and MUST say so explicitly."
  - *Informative*, after §7.1 L489: "A host serializer may map its language's empty or nil value to JSON `null` rather than `{}`. An endpoint MUST encode an empty JSON object with a value its serializer maps to `{}` and MUST NOT rely on its language's empty-list or null value doing so."
- **Artifacts:** none required — golden 04 already pins the correct wire form. Optionally a `nullable` flag on contract.json `field_types`/`node_schema` members so linters can enforce the new rule mechanically.
- **Dropped:** the proposed new receiver rules for `"params":null` / `"result":null` — §7.3:519 already pins `-32602` for structurally invalid params, and "a receiver that receives a response whose `result` is `null` MUST treat that request as failed with `-32603`" is malformed (a response receiver does not answer with an error code).

---

### P2-6. §19 defines no outcome for a splice the Emacs document refuses, and the recovery it mandates installs the refused edit as the shared baseline
**Dimension: editor-sync-positions (CONFIRMED).**

- **Claim:** `edit.delta` is a notification with no error channel; §19.3's mandated recovery (`edit.resync`) returns the *Companion's* state at `seq: 0` with prior history discarded — i.e. the very text Emacs just refused — and §19.2's post-resync path never triggers §19.2 L2645-2650's reconciliation duty, which is scoped to `edit.open`.
- **Sections touched:** §19 preamble, §19.3 (2676–2678), §19.4 (2730–2733, 2748–2752), §19.2 guarantee (2617–2618).
- **Emacs evidence:** `emacs-30.1:src/insdel.c:2009` `prepare_to_modify_buffer_1` — the gate every text-modifying primitive routes through — does `if (!NILP (BVAR (current_buffer, read_only))) Fbarf_if_buffer_read_only (temp);` at `:2016-2017` and calls `verify_interval_modification` at `:2037/:2042`, which reaches `src/textprop.c:67-72` `text_read_only` → `xsignal1 (Qtext_read_only, propval)`. So a document can refuse a splice wholesale *or for a sub-range only*, and the sub-range case has no EBP representation at all (§17.4's `read_only` is a whole-node authored boolean).
- **Consequence:** both endpoints believe they are synchronized at `seq: 0` on texts that differ — the permanent silent divergence L2617-2618 forbids. The two escapes an implementer reaches for are both unstated: bind `inhibit-read-only` (silently defeating protection the user or mode set — a §23.1 concern, since the Companion is the less-trusted end), or reassert after resync (correct, but no sentence requires it).
- **Proposed amendment:**
  - §19.3, after L2678: "Resynchronization adopts the Companion's state. An endpoint whose authoritative document **refused** the splice — as opposed to one whose view merely fell out of sequence — MUST NOT let that adoption stand: after the resynchronization completes it MUST, at the new `seq: 0`, issue the `edit.apply` that restores its authoritative text. An endpoint MUST NOT suppress or override a document's own write protection in order to apply a received splice."
  - §19 preamble (shape 1): "Where a document is not writable in full, Emacs SHOULD present the synchronized `editor` with `read_only: true`; sub-document write protection has no representation in this protocol, and a Companion is entitled to treat an editor it was not told is read-only as fully writable."
- **Artifacts:** none — no new member, status, or `data.reason`. The reassert behavior belongs in §24.6's adversarial list rather than goldens (which hold single-frame canonical rows and wire negatives, not multi-message sequences).

---

### P2-7. §9.2's "cryptographically random" names a property with no checkable criterion, and the host's only unconditional CSPRNG route is a side door
**Dimension: pairing-crypto (CORRECTED).**

- **Claim:** §9 demands CSPRNG-derived values in four places (§9.1 L597-598, §9.2 L667 and L689-690, §15.1 L1460, §20.4 L2583) and nowhere says what disqualifies a generator; §26 cites no randomness reference. Nothing in §24.6 or goldens/ (fixed nonces by design) can distinguish a conforming generator from a non-conforming one.
- **Emacs evidence:** `emacs-30.1:src/sysdep.c` — `typedef unsigned int random_seed;` / `set_random_seed → srandom (arg)`, `init_random` seeding from `getrandom(&v, sizeof v, 0)` or, on failure, `getpid () ^ tv_sec ^ tv_nsec`, and `get_random` concatenating 31-bit `random ()` outputs. `src/gnutls.c:3099-3110` registers `gnutls-hash-mac` only under `#ifdef HAVE_GNUTLS3` inside `#ifdef HAVE_GNUTLS`, and GnuTLS is a packager-supplied ndk-build add-on on Android (`java/INSTALL`). The unconditional route is the `iv-auto` input to the always-present `secure-hash` (`src/fns.c:6259-6281`, `ssize_t gotten = getrandom (p, lim - p, 0);` reached via `extract_data_from_object` at `fns.c:6305`), or reading the platform entropy device (`src/androidvfs.c:64-67` intercepts only `/assets` and `/content`).
- **Note in Emacs's favor:** `doc/lispref/numbers.texi` at 30.1 explicitly de-advertises `random` for this use ("On typical platforms the random seed contains only 32 bits… not nearly enough for cryptographic purposes") — while naming no replacement. The divergence risk is an implementer ignoring the manual, not the host steering them wrong.
- **Proposed amendment** (§9.2, replace L689–690; shape 3 + shape 4):
  > Each nonce MUST encode 16 octets drawn from the platform's cryptographic random source and MUST be used for only one transport connection. The generator MUST be one whose future outputs remain unpredictable to a party that has observed any number of its previous outputs; a generator seeded once from a value narrower than 128 bits, or a language's default pseudo-random facility not documented as cryptographic, does not satisfy this requirement. The same requirement applies to the pairing token and pairing ID of Section 9.1 and to every other value this specification requires to be CSPRNG-derived (Sections 15.1, 20.4).

  *Informative:* some host environments expose a fast default pseudo-random function seeded once from the operating system and unsuitable here, while their cryptographic source is reachable only indirectly — through an optional cryptography module, through a hash or cipher primitive that accepts an auto-generated-IV input, or by reading the platform entropy device. Implementers SHOULD confirm which the deployment build provides, and SHOULD fail pairing rather than fall back.
- **Also:** add RFC 4086 / BCP 106 to §26 so the property has a normative anchor. No contract.json or goldens change.

---

### P2-8. §9.3's "constant time" MUST names an operation Emacs has no primitive for, and the spec never defines it operationally — which also hollows out amendment #79's equal-work path
**Dimension: pairing-crypto (CORRECTED — the microarchitectural half of the proposed fix removed as unachievable).**

- **Claim:** §9.3 L738 ("Both endpoints MUST compare well-formed proofs in constant time") is the only occurrence of the term besides §9.2 L676-680, and neither defines it. It will be discharged by `string=`, which is the one call that reads as "compare the proofs."
- **Emacs evidence:** `emacs-30.1:src/fns.c:355-358` `Fstring_equal` — `if (SCHARS (s1) != SCHARS (s2) || SBYTES (s1) != SBYTES (s2) || memcmp (SDATA (s1), SDATA (s2), SBYTES (s1))) return Qnil;`; `Fcompare_strings`'s docstring (`fns.c:378-381`) is an explicit early-exit contract ("- 1 - N is the number of characters that match at the beginning"). `git grep -iE 'constant.time|memcmp_const|secure_compare|timingsafe' emacs-30.1 -- src/ lisp/` returns only `itree.c` and two games: **no constant-time helper exists at 30.1.**
- **Why it bites:** on-device loopback gives an attacker high-resolution local timing, §9.1's rate limit is stated without a bound, and amendment #79's carefully constructed dummy-key HMAC path is worthless if the comparison it names early-exits identically in both branches. Proofs are fixed-length (§4.4 L181-182, 64 lowercase hex), so the accumulate-over-all-positions discharge is genuinely available to both endpoints.
- **Proposed amendment** (§9.3, replace L738; shape 3):
  > Both endpoints MUST compare well-formed proofs without leaking, through control flow or data-dependent branching, how many leading characters matched. Because both proofs are fixed-length lowercase hexadecimal (Section 4.4), an endpoint MUST compare them by examining every character position of both values and combining the per-position differences into a single result tested once at the end, and MUST NOT use a comparison that returns as soon as a difference is found. The same rule applies to the comparison on the unknown-pairing-ID path of Section 9.2. This requirement is stated at the level of the endpoint's own program; this specification does not require an endpoint to eliminate timing variation introduced by its host language runtime, memory manager, or processor, though an endpoint SHOULD prefer a platform-provided constant-time comparison where one exists.

  *Informative:* most host languages' built-in string-equality operations return at the first differing element and do not satisfy this requirement; the portable discharge is to accumulate a bitwise difference across all 64 positions and test the accumulator once.
- **Artifacts:** goldens — add two vectors beside `02-handshake.bin`: a `client_proof` differing only in its **final** hex character and one differing only in its **first**, both expecting `1203`. That pair makes the duty testable rather than aspirational. §24.6 item 6 gains the final-character case. No contract.json change.
- **Dropped:** "resistance to timing variation below the program level is REQUIRED for the Companion" — unachievable by any conforming endpoint on a managed runtime and an out-of-order CPU; it would create a second by-construction non-conformance.

---

### P2-9. §17.2 pins no base64 alphabet, padding, or line-break rule for `image.data`, and the canonical Emacs encoder line-wraps at 76 columns by default
**Dimension: widgets-render-model (CONFIRMED).**

- **Claim:** §17.2 L1919-1924 requires the Companion to "validate the media type and decoded bytes" of a `data:image/*` URL Emacs authors, but never states the base64 profile. A strict decoder rejects the **entire surface** with `1201` (§16.1 L1758-1766 forbids normalizing); a MIME-tolerant decoder renders. One wire byte, two conforming outcomes, one of which loses the whole snapshot.
- **Emacs evidence:** `emacs-30.1:src/fns.c:4141` — `return base64_encode_string_1 (string, NILP (no_line_break), true, false);` — the one-argument call `(base64-encode-string BYTES)` therefore passes `line_break = t`, and `fns.c:3948`/`:4223-4232` wrap with a literal `\n` every 76 output characters (`#define MIME_LINE_LENGTH 76`). Note the contrast with `Fbase64url_encode_string` at `fns.c:4144`, whose optional arg is NO-PAD — the two encoders differ on **both** axes the spec leaves open.
- **The spec already knows this needs pinning:** §20.3 L2925 says `icon_png` is "standard padded [RFC4648] base64 of a PNG"; §17.2 is the unpinned outlier, and even §20.3's wording does not resolve line breaks. RFC 2397 is not in §26 at all.
- **Proposed amendment** (§17.2, after L1924):
  > The base64 payload of a `data:` URL MUST use the standard [RFC4648] alphabet with padding, MUST NOT be the base64url alphabet, and MUST NOT contain line breaks or any other whitespace; a sender MUST emit it as a single unbroken run. A Companion MUST reject a payload containing a character outside that alphabet and MUST NOT strip or normalize whitespace in place of rejection. A Companion MAY additionally accept a payload whose only extra characters are line feeds, provided it applies the same media-type, byte-count, and pixel limits after decoding; this tolerance is OPTIONAL and a sender MUST NOT rely on it.

  *Informative:* several host base64 encoders wrap output at a fixed column by default and require an explicit argument to suppress it; the tolerance exists so a sender's default-argument mistake degrades to a rendered image rather than whole-snapshot rejection. Apply the same no-whitespace clause to §20.3 L2925.
- **Artifacts:** goldens — `goldens/widgets.golden` uses only `https://` image URLs (lines 5–7); add one `image` node with a short canonical unbroken padded standard-alphabet `data:image/png;base64,` URL. contract.json — add `image_data_encoding: {"alphabet":"rfc4648-standard","padding":"required","whitespace":"forbidden"}` beside `image_media_types`. §24.6 — a line-wrapped payload belongs in the required adversarial tests.

---

### P2-10. §17.7's `line` promote/demote is built on a bullet/heading model org does not have: promote manufactures a top-level headline that demote cannot undo
**Dimension: widgets-render-model (CONFIRMED).**

- **Claim:** §17.7 L2275-2281 asserts promote and demote are inverse "steps"; against org's actual grammar they are not, and the corrupted intermediate flows to Emacs through §19 (L2272).
- **Emacs evidence:** `emacs-30.1:lisp/org/org.el:113` `(defvar org-outline-regexp "\\*+ ")` and `:116` `"^\\*+ "` — stars anchored at column 0 **and followed by a space**; `lisp/org/org-list.el:364` `org-list-full-item-re` uses the bullet class `\\(?:[-+*]\\|…\\)` and `:388-389` `org-item-re` builds the `*`-bullet alternative as `[ \t]+\\*` — a `*` bullet is a legal list item precisely when **indented**.
- **Traced by hand:** `"  * sub item"` matches `org-item-re`; §17.7 promote branch 2 strips two spaces → `"* sub item"`, which now matches `^\*+ ` exactly — a level-1 headline. demote then takes branch 1 → `"** sub item"`. `promote∘demote` is not the identity. Separately, `"+ item"` is a legal org bullet that promote de-indents but demote (which enumerates only `-`) can never restore. And on a single-star line the missing space requirement corrupts emphasis: `"*bold* text"` → `"**bold* text"`.
- **Proposed amendment** (§17.7, replace L2275–2281, literal-text rules only, no org dependency in normative text):
  > `promote` reduces its outline depth by one step: a line beginning with two or more `*` characters **followed by a space** loses one leading `*`; otherwise a line beginning with two or more leading spaces loses two of them, **except that a line whose first non-space character is `*` MUST NOT be de-indented to column 0 and is instead unchanged**; a line already at minimum depth is unchanged. `demote` raises it by one step: a line beginning with one or more `*` characters **followed by a space** gains one leading `*`; otherwise a line whose first non-space character opens an unordered (`-`, `+`, or `*`) or ordered (`N.` or `N)`) list item gains two leading spaces; any other line whose first character is a space gains two leading spaces; any other line is unchanged. Within one line these two operations MUST be inverse: applying `demote` then `promote`, or `promote` then `demote`, MUST restore the exact original text whenever the first of the pair changed it.

  *Informative:* the exclusion protecting a `*`-prefixed line from reaching column 0, and the space requirement on the `*` heading form, exist because in common outline text a `*` at column 0 followed by a space denotes a heading while the same bullet indented denotes a list item.
- **Artifacts:** contract.json unchanged (`toolbar.line_ops` vocabulary is unaffected). goldens carry no `line` op today; add a promote/demote round-trip vector. Prose-only amendment in the shape of SPEC-CHANGES #62.

---

### P2-11. `on_point_tap` injects only the authored point object, so the tapped point is not reliably identifiable — while §17.5 computes the ordinal index and discards it
**Dimension: surfaces-actions-state (CORRECTED — "unresolvable by construction" softened; `meta` is a partial escape).**

- **Claim:** §14.3 L1396 gives `on_point_tap` only `value`, while every peer index-bearing hook injects an index (`on_reorder` → from/to/order at L1391, `on_add_row`/`on_add_col` → index at L1393) — and amendment #55 made §17.5 L2152-2154 resolve the tap to an **ordinal index in the first series**, then dropped it from the wire.
- **Why value-identity is unsound:** (a) §17.5 L2147-2149 requires only finite numeric `x` and `y` and imposes **no distinctness** among points, so `[{x:0,y:5},{x:0,y:5}]` is legal and no comparator can disambiguate; (b) SPEC.md:125 makes member order insignificant and §4.3 makes `1` and `1.0` equal, so a conforming Companion may echo the point permuted or renumbered.
- **Emacs evidence:** `emacs-30.1:lisp/jsonrpc.el:632` decodes `:object-type 'plist`, preserving wire member order, and `src/fns.c` `internal_equal` returns false on `XTYPE` mismatch before comparing values, with the `Lisp_Cons` arm walking CAR/CDR pairwise — verified `(equal '(:x 1 :y 2) '(:y 2 :x 1))` ⇒ nil.
- **Partial escape the spec does offer:** authors MAY carry identity in the optional `meta` object, which §17.5 requires the Companion to echo in full. So this is an unnecessary author burden and a trap, not a hard impossibility.
- **Proposed amendment:**
  - §14.3 L1396: `| `on_point_tap` | `value` as the authored point object and `index` as that point's zero-based ordinal index in the first series |`
  - §14.3, after L1408: "For `on_point_tap`, `index` is the ordinal index Section 17.5 resolves the tap to, in the first series of the tapped `chart`. A receiver SHOULD use `index` to identify the tapped point; the echoed `value` is convenience data and is not an identity, since Section 17.5 does not require authored points to be distinct."
  - §17.5 L2154: cross-reference "The resolved index is injected as Section 14.3 specifies."
- **Artifacts (required):** contract.json — `actions.injections.on_point_tap` from `["value"]` to `["value","index"]`, so the authored-conflict linter rejects an Emacs-authored `args.index` on that hook. goldens — the widgets chart case must carry the injected `index` in its expected `event.action.args`. §25 classification: restricts previously valid content.

---

## P3 — five entries

### P3-1. Negative goldens assert one unconditional outcome per vector while §24.2/§6.2 scope those duties per role; `manifest.json` has no role dimension
**Dimensions converged: error-model + conformance-goldens** (both corrected to artifact-level after the verifiers found §24.2:3606-3607 already carries the scoping).

- **Claim:** §24.5's Golden-identity list (3661–3667) has no role bullet, so `goldens/wire/manifest.json` hard-codes one `expect_error` per fixture — and five are unproducible by a conforming Emacs endpoint that elects §6.2's delegation.
- **Measured on GNU Emacs 30.1 against the repository's own fixture bytes:** `19-duplicate-members.bin` → silently accepted, first-wins under `plist-get` (`(json-parse-string "{\"a\":1,\"a\":2}" :object-type 'plist)` ⇒ `(:a 1 :a 2)`; the same call with the default hash-table type is *last*-wins, sharpening the divergence); `21-deep-nesting.bin` → silently accepted (`src/json.c:767`, `available_depth = 10000`); `16`/`17` → dropped with a warning, no `-32700` frame (`jsonrpc.el:766-770`); `18-batch-array.bin` → internal `(wrong-type-argument plistp [1 2])` at `jsonrpc.el:773-775`, no frame at all; `11`/`12`/`14` behave as recorded in P2-1. Manifest expects `parse-error`/`parse-error`/`invalid-request`/`invalid-request`/`parse-error`/`close`/`close`/`close`.
- **Proposed amendment** (artifact-level; §2.2:57-60 already names this condition):
  - §24.5 identity list, fourth bullet: "- the receiver role or roles for which that expectation is normative."
  - §24.6 preamble (3678), one clarifying sentence pointing at §24.2's scoping so a suite author need not reconstruct it.
  - **Note:** the *normative* half of this cluster — that an excused role still owes a bounded terminal reaction — is folded into **P2-1 edit 3** and should not be ratified twice.
- **Artifacts (required):** `goldens/wire/manifest.json` gains a per-fixture `roles` / `applies_to` key (default: both roles when absent, leaving the eleven close/incomplete-frame fixtures unaffected), set to `["companion"]` on 11, 12, 14, 16, 17, 18, 19, 21; negative entries MAY gain a `tolerated` array naming the alternative bounded outcomes (e.g. `12-duplicate-length: ["accept-last"]`). `validate.py` `check_wire` (387–414) and both fixture runners must learn the key and skip the response assertion for a delegating Emacs endpoint while still asserting stream synchronization and non-action. No contract.json change.

---

### P3-2. §24.6 has no vector exercising a §4.3 comparison whose operands spell an equal value differently
**Dimension: surfaces-actions-state (CORRECTED — §4.3 itself needs no normative change).**

- **Claim:** §4.3 is precise and complete (`1` = `1.0` = `1e0`, `-0` = `0`, member order irrelevant), and a conforming comparator is a ten-line function. What is missing is a **test**: nothing in §24.6's 14 items or in goldens/ distinguishes a §4.3-conforming endpoint from one that delegates to a host primitive.
- **Emacs evidence:** `emacs-30.1:src/fns.c` `internal_equal` — `if (XTYPE (o1) != XTYPE (o2)) return false;`; `same_float` compares *representations* ("This looks at X's and Y's representation, since (unlike `==`) it returns true if X and Y are the same NaN"); `Feql`'s docstring states "(eql 0.0 -0.0) returns nil". Verified: `(equal 1 1.0)`⇒nil, `(equal -0.0 0.0)`⇒nil, `(seq-contains-p [1 2 3] 2.0)`⇒nil, `(seq-uniq '(1 1.0))`⇒`(1 1.0)`. So `equal`, `eql`, `member`, `assoc`, `seq-uniq`, `delete-dups` and equal-tested hash tables all violate §4.3 on the exact values §13.6:1231, §14.6:1563-1568 and §17.4:2043 require compared.
- **Proposed amendment:**
  - §24.6, new item: "a Section 4.3 comparison whose operands use differing spellings of equal values (`1` versus `1.0` versus `1e0`, `-0` versus `0`) and objects differing only in member order, exercised through input-draft reconciliation (Section 13.6), `state.changed` reconciliation (Section 14.6), and enum-option distinctness (Section 17.4)."
  - §4.3, clearly-marked informative note: "many host runtimes' structural-equality primitives are representation-sensitive for numbers and order-sensitive for decoded objects; implementations generally need a purpose-built comparator."
- **Artifacts:** goldens — a discrete `slider` authored `values: [1,2,3]` plus a `state.changed` carrying `value: 2.0` that MUST reconcile as compatible; an `enum_list` whose options carry `1` and `1.0` expecting `1201` (duplicate option value under §4.3). `validate.py`'s option-distinctness check must switch to a §4.3 comparator. No contract.json schema change.
- **Note on live risk:** in the *deployed* configuration (Kotlin/org.json Companion, which parses `2` to Integer and re-emits `2`, plus §17.4:2131's "MUST return the exact selected authored number") the collision is theoretical. It is a conformance-suite gap, not a live data-loss path — which is why it is P3, not the P2 the dimension originally proposed.

---

### P3-3. §21.5 never scopes what `policy: "queue"`/`"wake"` durability guarantees for transition-driven triggers, and Emacs is given no way to learn an observation gap occurred
**Dimension: device-capability-triggers (CORRECTED).**

- **Claim:** §21.1:3053 ("Accepted registrations MUST persist across Companion and device restarts") and :3056-3058 read with §15's durable-queue vocabulary invite an author to model `power`/`screen`/`network`/`battery.level` + `queue` + `ttl_s` as guaranteed eventual delivery of every platform edge — while §21.5:3257-3258 already means an edge occurring while the Companion was not executing is absorbed into the restored baseline and can never fire. §21.8's `trigger_unavailable` covers only permission revocation, so nothing on the wire distinguishes "no transitions occurred" from "the Companion was dead for six hours." The spec makes the concession explicitly for `time` (3284–3290, coalesced catch-up) and not for the transition types.
- **Platform evidence:** `emacs-30.1:doc/emacs/android.texi:474-477` "Application processes are treated as disposable entities by the system"; :483-488 the permanent-notification workaround; :498-504 "it is not guaranteed that the system will not kill Emacs… many manufacturers institute additional restrictions." (This is testimony about the platform drawn from Emacs's manual and applied to the Companion, a different app — legitimate platform evidence, not Emacs-endpoint behavior.)
- **Proposed amendment** (§21.5, after L3260):
  > Durability under `policy: "queue"` and `policy: "wake"` applies to occurrences the Companion observed and admitted under Section 21.2; it does not guarantee that every platform transition, threshold crossing, or calendar boundary is observed. A transition that occurs while the Companion is not executing is not observed, and re-establishing the baseline at restore absorbs it. A Companion MUST NOT present a transition-driven trigger type as a complete event log.

  *Informative:* on platforms treating application processes as disposable, with vendor-specific background-execution restrictions, the observation gap can span hours; `time` (whose missed intervals are coalesced above) or `state.get` sampling is the completeness-preserving alternative.
- **Dropped:** "the Companion MUST NOT synthesize such an occurrence" (already implied by 3257-3258) and "Emacs MUST NOT rely on a transition-driven type for correctness-critical delivery" (unenforceable normative MUST on an endpoint's internal design).
- **Artifacts:** none.

---

### P3-4. Permission identifiers in `device.trigger_unavailable` are never required to resolve against `device.permissions`
**Dimension: device-capability-triggers (CORRECTED — opacity is already covered by SPEC.md:176; the linkage and stability are not).**

- **Claim:** `trigger_unavailable` (§20.1:2842, §21.8:3389-3391) is the sole wire channel telling Emacs a supported trigger cannot arm, but nothing requires its values to appear as keys of `device.permissions`, to be `false` there, to match §8:581's `data.permission` on `1002 cap-permission`, or to remain stable across Companion upgrades. Two Companions can both conform while an Emacs-side remediation affordance key-misses under both.
- **Grounding:** the real vocabulary on the target platform is fully namespaced (`java/AndroidManifest.xml.in` declares `android.permission.POST_NOTIFICATIONS`, `RECEIVE_SMS`, `READ_CALENDAR`, `READ_PHONE_STATE`, `READ_CALL_LOG`, `ACCESS_NOTIFICATION_POLICY`, `WRITE_SETTINGS`, `RECEIVE_BOOT_COMPLETED`; `doc/emacs/android.texi:535`/`:691` reproduce the same spelling), while SPEC.md:2817's example writes `"permissions": {"post_notifications":true}` — a third spelling. contract.json (format 6) projects no permission vocabulary at all.
- **Proposed amendment** (§20.1, after L2847):
  > Every identifier appearing in a `device.trigger_unavailable` array MUST also appear as a key of `device.permissions` with the value `false` at the time the welcome is sent; a Companion MUST NOT report a blocking identifier absent from the snapshot. A Companion MUST use the same identifier for the same platform grant in every welcome it sends for a pairing identity, across sessions and across Companion upgrades, and SHOULD use the same identifier in `data.permission` on `1002 cap-permission` (Section 8).

  *Informative* (§21.8): because these identifiers are opaque (Section 4.4), the Companion owns the user-facing remediation path; an Emacs endpoint offering one SHOULD invoke `settings.open` rather than render an identifier as a user-visible permission name.
- **Artifacts:** none (the vocabulary stays deliberately unprojected — say so in the SPEC-CHANGES row so a future projector does not try to enumerate it). No golden exercises a device report.
- **Dropped:** the opacity clause of the original proposal — SPEC.md:176 and §4.1 already say it.

---

### P3-5. §23.2's no-remote-evaluation list enumerates only execution sinks and omits *interpretation* sinks
**Dimension: security-elisp-surface (CORRECTED — the severe half refuted).**

- **Claim:** §23.2's five bullets (eval, untrusted-input execution, ambient dispatch, shell, deserialization) are all evaluation/execution. None covers using a received string as the *format, template, query, or pattern* that the host interprets, rather than as an inert argument to one — precisely the idiom §7.3 L512/L520-522 invites by requiring unknown methods and invalid params to be logged.
- **Emacs evidence:** `emacs-30.1:src/editfns.c` `styled_format` — `:3598` `error ("Format string ends in middle of format specifier")`, `:3612` `error ("Not enough arguments for format string")`, `:3777` `error ("Invalid format operation %%%c", …)`, and no field-width cap. `lisp/jsonrpc.el:320` dispatches notifications **bare** — `(funcall ndispatcher conn (intern method) params)` — with no `condition-case` (contrast the request arm at 303–316), so such a signal escapes message dispatch.
- **Honest scoping:** the bare-template idiom `(message (concat "unknown method: " m))` yields a **signal**, not the 100 MB allocation; the allocation (`(length (format "%99999999d" 1))` ⇒ 99999999) requires a call that also supplies an argument. The blessed library does not commit the bug — `jsonrpc--warn "Invalid JSON: %s %s"` and `jsonrpc--log-event`'s formats all pass wire text as an argument. And §23.1 L3509-3511 already binds the endpoint to "validate… every other received value before use." This is editorial hardening of an enumeration, not an interop or exhaustion hole.
- **Proposed amendment** (§23.2, one bullet before the shell-command bullet at L3521, phrased for any host language):
  > - use a received string as a format, template, query, or pattern that the host interprets — a printf-style or equivalent format string, a log or message template, a database query, or a regular expression — rather than passing it as an inert argument to such a construct;

  *Informative:* on some hosts, format primitives signal on a stray `%` and honour an arbitrary field width, and a notification dispatcher may run without an error barrier, so such a signal escapes message dispatch.
- **Artifacts:** none required; §24.6 item 4 (unknown-notification dispatch) is the natural place for a suite to send a `%`-bearing unknown method name.

---

## The one change that matters most, and why

**Bound the §6.2 delegation clause — SPEC.md:462–470 — along three axes it currently leaves open: strictness only (never diagnostics), never resource commitment, and never non-termination.**

That single paragraph is the root cause of the largest finding cluster in this review. Thirteen of the 31 surviving findings trace back to it: P1-1 (secrets logged), P1-2 (interning), P2-1 (header stall + unbounded buffering), P2-2 (unanswered request on encode failure), P2-4 (octet accounting), P2-5 (`{}` and absent-vs-null), P3-1 (goldens roles). Its current text relaxes "the receiver obligations of this section, together with Section 4.1's duplicate-member and encoding rejections… accepting that library's tolerances," and disclaims relaxation only for "Section 6.1." Two structural problems follow:

1. **"Tolerances" is doing work it cannot bear.** Three of the behaviors it appears to bless are not leniency at all — they are *non-termination* (the 100-octet header stall, the never-completing declared body), *permanent resource commitment* (obarray interning before validation), and *disclosure* (the events buffer). A tolerance is "I accepted something I could have rejected." None of these is that.
2. **Naming §6.1 alone invites the *expressio unius* reading** that §7's sender obligations and §23's security obligations are relaxed for a delegating endpoint. They are not, and the blessed library breaks several of them by default.

The minimal fix is three sentences, all in existing house shapes, all implementation-agnostic:

> No sender obligation **in this document** is relaxed by this paragraph. A role excused by this paragraph from a strictness obligation still owes a bounded terminal reaction: it MUST NOT accept the message as valid, and it MUST reach close, discard, or a documented tolerance within Section 22.3's bounds; an unbounded stall is not a conforming alternative. This paragraph does not relax any obligation of Section 23, and in particular does not extend to a host library's diagnostics or to resources it allocates before validation.

Every P1 and most P2 amendments above then become local elaborations of a coherent rule rather than a scattering of patches. It is also the cheapest change in the list: one paragraph, no contract.json change, no golden change.

---

## On stating an Emacs version floor

Two dimensions raised it; they reach opposite conclusions on different clauses, and both are right.

**FOR a normative floor — conformance-goldens, and it is the stronger argument.** §4.5's own delegation carve-out (SPEC.md:202-212, amendment #35: "a host JSON-RPC library that bounds recursion by its own means") is **factually true only from Emacs 30 onward**. `json.o` is unconditional in `emacs-30.1:src/Makefile.in`, but in `emacs-29.1:src/Makefile.in` it is gated behind `JSON_OBJ = @JSON_OBJ@`; when the built-in is absent, `jsonrpc.el` silently degrades to `json.el`'s **recursive** `json-read`, and the bounded-recursion premise the carve-out rests on evaporates without any diagnostic. That is a normative clause whose truth value depends on the host version, which is exactly the case for a floor. The right home is **§24.2** (the Emacs core-conformance section), not §4.5 and not §1: something of the shape "An Emacs endpoint claiming core conformance under this section MUST provide a JSON decoder that bounds recursion internally; the host's built-in decoder satisfies this from Emacs 30.1 onward, and an endpoint on an earlier host MUST supply its own." Note this is a *conformance* statement, not a normative dependency on Emacs in the protocol text — §24.2 is already the Emacs-specific section, so it does not violate the implementation-agnostic rule.

**AGAINST a floor for the crypto primitives — pairing-crypto.** The feared build-conditional dependency does not exist. `gnutls-hash-mac` is registered only under `#ifdef HAVE_GNUTLS3` inside `#ifdef HAVE_GNUTLS` (`src/gnutls.c:3099-3110`) and GnuTLS is a packager-supplied ndk-build add-on on Android — but `secure-hash` is unconditional core and returns 32 raw octets under the BINARY argument (verified), so RFC 2104 HMAC-SHA-256 is constructible in pure Lisp on **every** 30.1 build and §24.6's KAT item 6 is passable without GnuTLS. No floor or build-conditional language is warranted in §9. (The same `secure-hash`/`iv-auto` path is the unconditional CSPRNG route noted in P2-7, reinforcing this.)

Two other version-sensitive facts, for the record, neither of which needs a floor: `json_serialize`'s 50-container cap is unchanged on master, so it is not a defect a floor could fix (P2-2); and `jsonrpc.el`'s 100-octet header bound is identical at 29.1:591, 30.1:743, 30.2:743 and master:829, so it is likewise not version-specific (P2-1).

---

## Verification status and what still needs a human

- **No finding came back UNVERIFIED.** 12 CONFIRMED, 19 CORRECTED. Every Emacs citation in this document was read at `emacs-30.1:` and, where the claim was behavioral, reproduced on the locally installed GNU Emacs 30.1.
- **Needs a human decision, not a verification:** the `max_node_depth` constant in P2-2 (20 levels) and the `max_send_header_bytes` constant in P2-1 (128 octets) are engineering choices derived from — but not dictated by — the measured host ceilings. Both are §25 "restricts previously valid content" changes.
- **Needs artifact-level verification before landing:** the contract.json and goldens impacts asserted in the corrections were reasoned from the artifacts but not re-run end to end. Specifically: `validate.py`'s `decode_stream` unterminated-header gap (P2-1), the absent node-depth walk (P2-2), and the `check_wire` role dimension (P3-1) were each read but the proposed fixes are untested.
- **Two evidentiary caveats recorded above that do not change any verdict:** the exported `EmacsDocumentsProvider` is gated on `MANAGE_DOCUMENTS`, so exposure requires the user to pick the file in the system picker (P1-4); and `EmacsThread` handles a null startup-argument array cleanly, which makes P1-3's inertness requirement easier to meet, not harder.

## Dropped

Carried no further, with reasons:

- **The colon-space header-grammar claim** (framing-transport). `search-forward-regexp` is an unanchored search; `X-Ebp-Trace:abc\r\n` is skipped and the frame delivered normally. Empirically false.
- **"`dialog_id` permanently wedged for the life of the connection"** (error-model). §18.1's `1201` fires only against a second *outstanding* request with that ID; the user's eventual submit frees it. Transient, not permanent.
- **"jsonrpc.el's 10-second timeout is non-disableable"** (lifecycle-timers). `jsonrpc-request` accepts `:timeout <n>` and the defcustom can be let-bound to nil. A default-value trap, not a by-construction violation — which is why P2-3 is P2.
- **"Retries collect `1600 queue-busy` forever, permanently frozen"** (lifecycle-timers). The Companion's replay is single-file and concludes on its own; each retry runs over a drained queue and makes progress.
- **A normative sender cap of 48 containers** (json-model / conformance-goldens). Hard-codes an Emacs-derived constant into implementation-agnostic text, and is unnecessary — core `json.el`'s `json-encode` serializes 64 containers fine, so the Emacs *endpoint* is not depth-limited, only the built-in C serializer is. Replaced by the informative note + node-depth row in P2-2.
- **"Resistance to timing variation below the program level is REQUIRED for the Companion"** (pairing-crypto). Unachievable on any managed runtime or out-of-order CPU; would manufacture a second by-construction non-conformance.
- **§4.3 normative strengthening** (surfaces-actions-state). §4.3 already specifies the required semantics exactly; the proposed "MUST NOT delegate to a representation-sensitive primitive" restates it with emphasis. Only the §24.6 test item survives, as P3-2.
- **§24.6-scoping as a normative contradiction** (error-model / conformance-goldens). §24.2:3606-3607 already carries §6.2's scoping into Emacs conformance, so the prose does not contradict itself. Demoted to the artifact-level P3-1, with the one genuinely normative piece (bounded terminal reaction) folded into P2-1 so it is not ratified twice.
- **The pre-auth severity of the octet-accounting injection** (framing-transport). §5.2's mutual-HMAC floor means a pre-auth injector gains nothing and a post-auth one is the Companion. P1 → P2.
- **`-32700`-with-`id:null` dead-ending in jsonrpc.el's filter** (error-model). Already blessed by §6.2 L462-469. Not reported.
- **`error.data` dropped by `jsonrpc-connection-receive`** (error-model). Real, re-verified, but already logged at `AUDIT-full-spec-RAW.md:2289`.
- **Response-with-unknown-id logged and dropped** (jsonrpc-conventions). Already an open hole in the prior audit.
- **Duplicate-member non-detection in `json.c`** (json-model). Real, but §6.2:462-469 already scopes it asymmetrically.
- **Android pre-auth connect race** (security-elisp-surface). Already Tier-2 item 18 of `AUDIT-spec-holes-2026-07-24.md`.

## Explicitly clean — recorded so they are not re-litigated

Areas checked against source and found sound: unpaired-surrogate rejection, strict UTF-8 rejection, `NaN`/`Inf` refusal on serialize, `-0.0` handling, raw-control-character and trailing-content rejection (`src/json.c`); §7.4's wire ordering on the blessed path (the LIFO push at `jsonrpc.el:778` and `timer--activate`'s equal-time LIFO insertion at `timer.el:182` cancel out); §7.2 request-ID uniqueness; `android.permission.INTERNET` present, so the §5.2 loopback dial is permitted; §5.3's wake *language* correctly hedged against freezer/doze; `EmacsService.onStartCommand`'s `startForeground` + `specialUse` making §10/§15's survival premise sound; §19.1's position unit already pinned to Unicode scalar values (no UTF-16 hazard exists in §17 or §19); the change-granularity mapping from `signal_after_change` onto §19.4's splice; the losing-apply rollback via `replace-buffer-contents`; text properties invisible to `json_out_string`; `false`-vs-absent distinguishable via `:false-object :json-false`; §16.5/§16.6 alpha imposing nothing on Emacs; §18.4's theme derivation declared Emacs-side policy; §17.5's visualization nodes requiring no image bytes; `android_parse_color`/`xw-color-values` identical to X, so color findings hold on Android; `android-notifications-notify` present at 30.1; `clipboard.read` well-motivated (Android 10+ denies unfocused clipboard reads); §21.5's `every_s ≥ 60` matching AlarmManager's clamp; §20.3's `intent.start` allowlist not undermined by `android-browse-url`; §23.2 direction-neutral and therefore binding on Emacs; §23.6's loopback characterization accurate; `print-circle` a non-issue; contract.json's `error_codes` an exact character-for-character projection of §8's 21-row table; and the §9.3 known-answer vector independently recomputed and correct (`03e270fd…c9c9fb43` / `e9333d48…b9be58ec`), matching `goldens/wire/02-handshake.bin` and its manifest.

---

# Appendix — completeness critic: what this review did NOT cover

A final agent audited the review itself for gaps, spot-checking with `git show` rather than speculating. Its findings are reproduced verbatim. **G1–G3 are new candidate findings that no dimension surfaced** and are the natural next round.

## Ranked completeness gaps

### G1. `src/process.c` was never opened — and it contains the two behaviors that decide whether §22.3's backpressure MUST and §7.4's dispatch ordering are implementable at all

Nothing in the result cites `process.c`. Two verified facts live there:

**(a) Emacs's only backpressure is a blocking spin that runs arbitrary Lisp.** `emacs-30.1:src/process.c:6820-6851` (`send_process`): on `would_block (errno)` it does `write_queue_push (p, cur_object, cur_buf, cur_len, 1); wait_reading_process_output (0, 20 * 1000 * 1000, 0, 0, Qnil, NULL, 0);` and loops until the whole message is out — no timeout, no error, no bound. And `wait_reading_process_output` runs timers on this call shape (`process.c:5423-5443`: *"Normally we run timers here. But not if wait_for_cell…"*, gated on `NILP (wait_for_cell) && just_wait_proc >= 0` — `send_process` passes `Qnil` and `0`).

**(b) Therefore inbound EBP frames are dispatched *inside* an outbound send.** `jsonrpc.el` defers dispatch to timers precisely so it can unwind (`emacs-30.1:lisp/jsonrpc.el:795-799`: *"do all this processing in top-level loops timer"*), and its own filter comment already flags the hazard: `:786-788` *"Saved parsing state for next visit to this filter, which may well be a recursive one stemming from the tail call to `jsonrpc-connection-receive` below (bug#60088)."* So on a Companion that stops reading, an Emacs `surface.update` blocks the runtime, and while blocked it dispatches `event.action` / `edit.delta` / `state.changed` handlers re-entrantly, each of which may itself send and recurse.

**Why it matters.** §22.3:3451-3453 "MUST apply transport backpressure before unbounded memory growth" and §22.2:3427-3430's "at most one **unsent** snapshot per surface" both presuppose an endpoint-owned outbound queue with a non-blocking send. Emacs has neither unless the implementer builds one. §7.4:525-528 requires dispatch "in receive order within their applicable ordered channel" but never says a dispatch is **atomic with respect to another dispatch** — with (b), handler N is suspended mid-mutation while handler N+1 runs to completion, so any two-step mutation (§19.3 apply-splice-then-bump-`seq`, §13.6 draft reconciliation, §14.6 flush-before-action) can interleave. Two conforming implementations diverge; this is category (b)+(d) and is nowhere in SPEC.md, SPEC-CHANGES.md, or either prior audit (grepped: no hit for `process.c`, `send_process`, `wait_reading`, `reentran`).

**What to check next:** whether §7.4 should gain "an endpoint MUST NOT begin dispatching a message while an earlier message's dispatch is suspended," and whether §22.3 needs the asymmetric-scope treatment for endpoints whose host send primitive is blocking.

---

### G2. Number-literal decoding cost — the same "allocate before validate" class as P1-2, on a mechanism nobody looked at (`src/bignum.c` + `lib/mini-gmp.c` never opened)

`emacs-30.1:src/json.c:1310-1325` (`json_parse_number`) accumulates digits into `byte_workspace` with **no length cap**; on overflow it calls `json_create_integer` → `string_to_number` (`:1250`) → `src/lread.c:4858` `make_bignum_str` → `src/bignum.c:439` `int check = mpz_set_str (b->value, num, base);`.

On the target build that is **mini-gmp**, whose base-10 conversion is quadratic: `emacs-30.1:lib/mini-gmp.c:1390-1402` (`mpn_set_str_other`) runs `cy = mpn_mul_1 (rp, rp, rn, info->bb);` over the *entire current limb count* once per digit group. `lib/mini-gmp.c` is in the tree, and `configure.ac:7410-7439` shows libgmp on Android is an `ndk_SEARCH_MODULE` add-on — `java/INSTALL:322` lists `gmp` alongside GnuTLS as a packager-supplied download, so the default Android build has no libgmp and falls back to mini-gmp. There is no `maybe_quit` anywhere in that loop.

**Why it matters.** §4.5:186-195 bounds the body (4 MiB), depth, node counts and identifier length, but places **no bound on a single number literal**; §4.2:138-141's ±2^53 rule is a *value* rule enforced after decoding. A single frame carrying a ~4-million-digit integer is inside every stated limit, and its conversion is ~10^10 limb multiplies inside `json-parse-buffer`, uninterruptible, before any §7.3/§11 check — reachable pre-auth by the same connect-race §23.6 concedes. This is P1-2's genre (`decoding MUST NOT let a peer's choice grow unbounded work before validation`) applied to CPU rather than to the obarray, and P1-2's proposed amendment text covers only *interning pools*, so it does not close this.

**What to check:** whether §4.5 needs a `max_number_literal_bytes` row (and a `limits.fixed` projection), and whether P1-2's new §23.5 paragraph should be generalized from "interning pool" to "any decode-time work or allocation superlinear in a peer-chosen token's length."

---

### G3. The transport's coding system is unpinned — the SPEC never requires the stream to be handled as untranslated octets, and the host's default for a network socket is *charset auto-detection*

`emacs-30.1:lisp/jsonrpc.el:515-549` (`initialize-instance`) sets buffer, filter and sentinel but **never** touches the coding system — grep for `set-process-coding-system` in 30.1's `jsonrpc.el` returns nothing. The process is created by the caller, and the default comes from `emacs-30.1:src/process.c:3270-3345` (`set_network_socket_coding_system`): with no `:coding` and no `coding-system-for-read`, decode falls to `XCAR (Vdefault_process_coding_system)`. Measured on GNU Emacs 30.1: `(undecided-unix . utf-8-unix)` under `LANG=C` and with no locale, `(utf-8-unix . utf-8-unix)` under a UTF-8 locale — i.e. **the decode side is locale-dependent and, in the common case, `undecided`**, meaning Emacs runs charset detection over peer-controlled octets. Verified that `undecided-unix` and `utf-8-unix` decode the same invalid-UTF-8 octets to *different* characters.

That this is a live implementer trap and not a theoretical one is settled by the one in-tree consumer: `emacs-30.1:lisp/progmodes/eglot.el:1590` passes `:coding 'utf-8-emacs-unix` explicitly.

**Why it matters.** This is the *root cause* of P2-4 (the review found the symptom — `position-bytes` accounting under-consuming — and its informative fix "open the connection in a binary coding system" happens to cure this too, but by luck: the analysis never identified that the coding system is unset, caller-chosen, and locale-varying). The EOL half is the more alarming one and I checked it: `src/coding.c:6490-6514` (`adjust_coding_eol_type`) would select `Qdos` and strip `\r` from a CRLF-only stream — which would make `jsonrpc.el:740`'s `\r\n` regexp never match, i.e. P2-1's permanent stall on the *first frame with no attacker*. **This does not fire at the defaults measured** (the eol type is already `unix` in every configuration I tested), so I am not reporting it as a break — but it is one `(setq default-process-coding-system (cons 'undecided ...))` or one `network-coding-system-alist` entry away, and neither SPEC.md nor the review says a word about it. SPEC.md's only mentions of CRLF are §6.1:394-398 (sender syntax); grep finds no "octet stream", "line ending", or "translation" requirement on the receiver's side of the socket.

**What to check:** whether §6.1/§6.2 should state (implementation-agnostically) that both endpoints treat the connection as an untranslated octet stream — no host-level newline translation, no charset detection, no decoding step between the socket and the framing parser — and whether P2-4's informative note should be promoted from "how to restore octet identity" to "pin the transport's byte handling before the first frame."

---

### G4. SPEC sections with **zero** coverage in the result

Never cited anywhere in the 21 amendments or the "explicitly clean" list:

§2.1, §2.3, §4.2 (only quoted through §4.3), §5.1, §10.1, §10.4, §13.1, §13.2, §13.3, §13.5, §13.7, §14.1, §14.2, §14.4, §14.5, §15.4, §16.2, §16.3, §16.4, §17.1, §17.3, §17.6, §18.2, §18.3, §18.5, §18.6, §19.5, §21.3, §21.4, §21.6, §21.7, §22.1, §22.2, §22.4, §24.3.

Judged against Emacs, most are Companion-side render/policy (§16.2-16.4, §17.1/17.3/17.6, §18.2/18.3/18.5, §21.3/21.6/21.7, §15.4) and are correctly out of scope for an Emacs-floor review. Three are worth a second pass:

- **§22.2 (traffic classes)** — folds into G1; the "unsent snapshot" model presumes a non-blocking outbound queue Emacs does not provide.
- **§19.5 (annotations)** — `fontify.show` runs "MUST be sorted, MUST NOT overlap, and MUST fit the synchronized text," Emacs-authored. Worth checking against `lisp/jit-lock.el`: fontification is driven from redisplay, so a synchronized buffer that is in no window has no faces to report unless the endpoint forces `font-lock-ensure`; and overlay-supplied faces (flymake, hl-line) *do* overlap, unlike text-property runs. Likely an informative note at most, but it is the only Emacs-authored member of the uncovered set.
- **§13.2 / §24.2:3610 ("persistent monotonic per-surface revisions")** — Emacs must persist a monotonic counter across restarts on a platform (`doc/emacs/android.texi:474-504`, already quoted in P3-3) that kills the process without notice. Nothing in the review checks whether the durability primitive exists at the Emacs endpoint; §24.2 asserts it as a conformance duty.

---

### G5. Claims asserted in the result whose source was never quoted — three spot-checked, all held

I re-derived the three that would have been most damaging if wrong; **all three confirm**, so no finding:

- "jsonrpc.el 1.0.25" — `emacs-30.1:lisp/jsonrpc.el:7` `;; Version: 1.0.25`. ✔
- "`secure-hash` returns 32 raw octets under the BINARY argument, so RFC 2104 HMAC is constructible on every 30.1 build" — `emacs-30.1:src/fns.c:6395` `DEFUN ("secure-hash", …, 2, 5, 0)` and `:6411-6413` *"If BINARY is non-nil, returns … a unibyte string whose length is half the number of characters"*. ✔
- "`EmacsService.onStartCommand`'s `startForeground` makes §10/§15's survival premise sound" — `emacs-30.1:java/org/gnu/emacs/EmacsService.java:203` `startForeground (1, notification);` in `onStartCommand` at `:177`. ✔

Still unquoted and **not** verifiable from Emacs source at all (they are Android-platform claims wearing Emacs clothing, and should be labelled as such before ratification): "§21.5's `every_s ≥ 60` matching AlarmManager's clamp"; "Android 10+ denies unfocused clipboard reads". Neither can be grounded in `emacs-30.1`; if an amendment rests on either, its evidence line is currently unsupported.

One adjacent check that came out **in the spec's favour**, recorded so it is not re-litigated: P2-7's "unconditional CSPRNG route" fails *safe*, not silently weak — `emacs-30.1:src/fns.c:6270-6276` `ssize_t gotten = getrandom (p, lim - p, 0); if (0 <= gotten) p += gotten; else if (errno != EINTR) report_file_error ("Getting random data", Qnil);`. And `src/json.c:1265-1268` (`json_create_float`) signals `Qjson_number_out_of_range` on overflow, so §4.2's infinity prohibition is enforced on the *parse* side too, which the review only checked on serialize.

---

### G6. Emacs subsystems still unopened after this pass

For a future round, ranked by residual risk: `src/keyboard.c` + `inhibit-quit`/`while-no-input` (can a `C-g` land inside a half-applied §19 splice?); `lisp/emacs-lisp/timer.el` beyond the single line 182 already cited (timer starvation under the G1 re-entrancy, and whether `run-at-time` deadlines survive Android CPU suspend — bears on §10.4 reconnection backoff and §21.5 `time` triggers); `src/thread.c` / `THREADS_ENABLED` (visible in `process.c:5734`'s Android `thread_select` branch — whether an Android build with threads changes G1's re-entrancy shape); `doc/lispref/processes.texi` (the documented contract for filter re-entrancy and `process-send-string` blocking, which is the citation an amendment would want); and `configure.ac`'s Android build-conditionals generally — `java/INSTALL:142-148` shows Emacs can be built against **API level 14** headers, which is worth one check against gnulib's `getrandom` replacement before §9 leans on it.