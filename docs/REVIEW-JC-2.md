# JC-2 implementation specification — `jetpacs-results.el` + `jetpacs-tablist.el`

Merged from four analyst extractions, hand-verified against poc-v1, the llm-poc-2 tree, and the Emacs 30.1 sources (`~/pkb/resources/emacs/emacs`, `git show emacs-30.1:…`).

**Status note (verified, not in the brief):** an untracked draft port already exists — `/home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-2/emacs/jetpacs-results.el` (465 L) and `.../jetpacs-tablist.el` (253 L) — plus `test/jetpacs-results-test.el` (364 L) and `test/smoke-results.el` (115 L), and `test/run-tests.sh` **already** byte-compiles both modules and runs the JC-2 ERT suite. The draft lands the mechanical drift, the exposure calls, the §16.2 degrades and `(revert-buffer nil t)`. This document is the authoritative target; every item is tagged **[done]** (draft matches) or **[OPEN]** (work remaining). Build the OPEN list.

---

## 1. Scope

**Delivers.** Two Tier-1 skins registered through JC-1's single dispatch seam (`jetpacs-render-buffer-register`), org-free, UI-free, depending only on `cl-lib` / `subr-x` / `tabulated-list` plus `jetpacs-widgets`, `jetpacs-surfaces`, `jetpacs-buffer`.

- `jetpacs-results.el` — the `next-error` substrate: occur / compilation (grep, rgrep, every `define-compilation-mode` derivative by derivation) / xref rendered as tappable locus cards; a tap replays **the row's own goto command** through `jetpacs-buffer-call-shimmed` so nothing pops a desktop window; the destination is framed and shown through a host seam; a prev/next stepper is armed. Two actions: `results.visit`, `results.step`.
- `jetpacs-tablist.el` — one skin for every `tabulated-list-mode` derivative: count + refresh row, per-mode header nodes, sort chips, one card per printed row tapping the **existing** `emacs.buffer.act`. Two actions: `tablist.sort`, `tablist.refresh`.

**Defers.**

| Deferred | To | Why |
|---|---|---|
| A real host for `jetpacs-results-visit-region-function` | JC-3a (`jetpacs-sections`) | poc's setter was out-of-manifest `jetpacs-emacs-ui.el:53`. JC-2 ships its own minimal default (`jetpacs-results-show-region` + `jetpacs-results-region-nodes`) so the rung is demonstrable. Arglist `(NAME BEG END LABEL &optional POINT)` is **frozen** by `jetpacs-sections.el:275`. |
| A producer for `jetpacs-results-set-file-loci` | JC-5/6 (`jetpacs-files`) | file-locus branch ships tested but unfed. |
| Consumers of the three tablist hook alists (`jetpacs-package-browser.el`) | later rung | hooks ship with a documented contract; see the §23.1 skin-contract requirement in §5. |
| `jetpacs-tablist-view-buffer-function`'s consumers (package-browser, tools, sql, project, hosts) | later rung | seam has **zero in-file callers**; see Decision 8. |
| A real `table` node rendering of a tabulated list | open design | poc emits no `table` anywhere; the format-6 `(KIND &rest cells)` drift is a non-event for this rung. |
| Widget-field taps reached through a tablist row | JC-4 dialog bridge | `jetpacs-buffer--widget-invoke` already signals "tap refused". |

---

## 2. `emacs/jetpacs-results.el` — public API, dependency order

Header: rung JC-2 of `docs/PLAN-jetpacs-consumers.md`. Requires `cl-lib subr-x jetpacs-widgets jetpacs-surfaces jetpacs-buffer`. **[OPEN]** the draft additionally `(require 'jetpacs-shell)` at :51 — drop it (Decision 4).

| # | Definition | Contract | Status |
|---|---|---|---|
| 1 | `(defcustom jetpacs-results-max-loci 300 :type 'integer :group 'jetpacs)` | Cap on locus cards from one buffer **and** on the `--loci` scan. `:group 'jetpacs` resolves (`jetpacs-surfaces.el:36`). | done (as cap only); **[OPEN]** make it bound the scan too |
| 2 | `(defcustom jetpacs-results-context-lines 100 …)` | Source lines shown **below** a visited locus. Read only by `--region-around`. | done |
| 3 | `(defcustom jetpacs-results-context-before 20 …)` | Source lines shown **above**. | done |
| 4 | `(defconst jetpacs-results-modes '(occur-mode compilation-mode xref--xref-buffer-mode))` | Dual duty: renderer registry **and** the §23.1 buffer allowlist. `xref--xref-buffer-mode` verified as the derived-mode name (`xref.el:1002`). Docstring must state both duties. | done |
| 5 | `(defun jetpacs-results--buffer-p (buf))` | Non-nil when BUF is live and derives from `jetpacs-results-modes`. **[OPEN]** use `(derived-mode-p jetpacs-results-modes)` — the LIST form is the advertised convention in 30.1; `(apply #'derived-mode-p …)` is the *deprecated* `&rest` shape (`subr.el:2849`, `advertised-calling-convention … "30.1"`). `apply` hides the arity so the compiler never warns. | **[OPEN]** |
| 6 | `(defun jetpacs-results--locus-pos (bol eol))` | Position on `[BOL,EOL)` carrying a jump, or nil. Probes text props `occur-target`/`compilation-message`/`xref-item`, char props `button`/`mouse-face`, then a `keymap`/`local-map` binding RET/`[return]`/`[mouse-2]`; line start first, then first non-blank. **Pure** — prime ERT target. | done |
| 7 | `(defun jetpacs-results--loci (buf &optional limit))` | `(POS . TEXT)` per locus row, POS actionable, TEXT the trimmed line, walking the **printed** buffer. **[OPEN]** add LIMIT (default `jetpacs-results-max-loci`) and stop there; **[OPEN]** pass TEXT through the §4.1 scalar sanitizer. | **[OPEN]** |
| 8 | `(defun jetpacs-results--index-of (loci pos))` | Index of POS in LOCI, or **nil** on miss (`cl-position … :test #'=`). Never 0-on-miss. | done |
| 9 | `(defun jetpacs-results-set-file-loci (loci))` | Store LOCI (plists `(:file PATH :line N :text S)`) as the active file set. **[OPEN]** validate shape at set time (string `:file`, integer `:line`) and stamp a generation counter (Decision 3). | **[OPEN]** |
| 10 | `(defvar jetpacs-results--file-set nil)` | Server-built set; cards address it **by index** so no path crosses the wire (§23.1 by construction). **[OPEN]** per-surface (Decision 2). | **[OPEN]** |
| 11 | `(defvar jetpacs-results--nav nil)` | `(:kind KIND :index I :count N :dest SRC-NAME)` + `(:buffer RESULTS-NAME \| :loci FILE-LOCI)`. Gates the stepper chrome. **[OPEN]** per-surface (Decision 2). | **[OPEN]** |
| 12 | `(defvar jetpacs-results--event-surface nil)` | The surface the in-flight event came from; bound by each handler around its effect. A handler runs outside `with-jetpacs-owner`, so `jetpacs-current-owner` is nil and a zero-arg push would hit `app:main` (D1). | done |
| 13 | `(defvar jetpacs-results-visit-region-function #'jetpacs-results-show-region)` | **THE host seam.** `(BUFFER-NAME BEG END LABEL &optional POINT)` — arglist frozen by JC-3a. Docstring must say: called from inside the jsonrpc dispatch extent, MUST NOT block. | done |
| 14 | `(defun jetpacs-results-show-region (name beg end label &optional point))` | Default seam: record `jetpacs-results--region` and re-push `jetpacs-results--event-surface`. **[OPEN]** re-push via `(funcall jetpacs-buffer-refresh-function SURFACE)` from a `run-at-time 0` continuation, not a direct synchronous `jetpacs-shell-push` (Decisions 4 + 5). | **[OPEN]** |
| 15 | `(defun jetpacs-results-region-nodes ())` | Nodes for the last visited region: label + stepper chrome + `jetpacs-buffer-render-region`. A host root includes it. | done |
| 16 | `(defun jetpacs-results--region-around (buf pos))` | `(BEG END LABEL POINT)` framing POS; LABEL `"buffer:line"`; POINT is the **line beginning**. Pure — ERT target (clamping, label, POINT). | done |
| 17 | `(defun jetpacs-results--card (name pos text))` | One tappable card. Calls `jetpacs-buffer-expose` for POS (§23.1). **[OPEN]** add `(jetpacs-with-attrs … :key …)` (§16.1); **[OPEN]** spend the §4.5 budget. | partial |
| 18 | `(defun jetpacs-results-render (buf))` | Count header + capped cards + cap note; `jetpacs-buffer-forget-exposed` **before** the cards. Fallback when no loci parse is `jetpacs-buffer-render` (the GENERIC renderer) — **never** `jetpacs-render-buffer`, which would recurse forever. **[OPEN]** budget participation. | partial |
| 19 | `(defun jetpacs-results--visit-command (pos))` | Text-property keymap's RET/`[return]`/`[mouse-2]`, else `current-local-map`'s. Must be called with the results buffer current. Pure — ERT target. | done |
| 20 | `(defun jetpacs-results--follow (buf pos))` | Places point, then `(jetpacs-buffer-call-shimmed cmd)`; returns `(DEST-BUF . DEST-POS)` or nil when the command never left BUF. **[OPEN]** wrap in the prompt-refusing macro (§5, P1) and pass an ON-ERROR thunk — `call-shimmed` swallows errors and always returns a cons (`jetpacs-buffer.el:785-816`), so "signalled" is otherwise indistinguishable from "went nowhere". | **[OPEN]** |
| 21 | `(defun jetpacs-results--show (dest index count nav-extra))` | Arm `--nav`, funcall the seam with `(NAME BEG END "LABEL · i/N" POINT)`, return t. **[OPEN]** `condition-case` the seam funcall: `jetpacs-shell-push` **signals** on any gate failure (`jetpacs-shell.el:448`), which would escape into the dispatch extent and answer `rejected` *after* the jump already happened, leaving `--nav` armed at a view that never opened. | **[OPEN]** |
| 22 | `(defun jetpacs-results--goto-buffer (results-buf loci index))` | Clamp `(max 0 (min index (1- count)))`, `--follow`, `--show`. Non-nil = jump landed. | done |
| 23 | `(defun jetpacs-results--file-dest (locus))` | `(BUFFER . POS)` via `find-file-noselect`, or nil. **[OPEN]** the worst D2 offender — see §5. | **[OPEN]** |
| 24 | `(defun jetpacs-results--goto-file (loci index))` | Same shape as #22 for the file kind. | done |
| 25 | `(defun jetpacs-results--nav-live-p (nav))` | Non-nil when the nav's source survives (`pcase` on `:kind`; unknown → nil). Pure. | done |
| 26 | `(defun jetpacs-results-buffer-view-actions (viewed-buffer-name))` | **Second public seam.** Prev/next chrome, only when a nav is armed, `viewed-buffer-name` `equal`s `:dest`, and the source is live; only the in-range direction at each end. Degrades `icon_button`→`button`. **[OPEN]** carry `:from I` (Decision 6). | partial |
| 27 | `(dolist (mode jetpacs-results-modes) (jetpacs-render-buffer-register mode #'jetpacs-results-render))` | Load-time registration. `setf (alist-get …)` **prepends** and `jetpacs-render-buffer` takes the first `derived-mode-p` match (`jetpacs-buffer.el:751-759`), so load order is precedence. | done |
| 28 | `(jetpacs-defaction "results.visit" (lambda (args params) …))` | §5. | partial |
| 29 | `(jetpacs-defaction "results.step" (lambda (args params) …))` | §5. | partial |

**Cross-file requirement (lands in `jetpacs-buffer.el`, JC-1, but is gating for JC-2):**

```elisp
(defmacro jetpacs-buffer-with-no-prompts (&rest body))   ; NEW, public
```
Runs BODY with `y-or-n-p` / `yes-or-no-p` / `read-string` / `read-from-minibuffer` / `read-file-name` / `read-multiple-choice` / `read-char-choice` / `read-passwd` / `completing-read` shadowed by signalling stubs, plus `large-file-warning-threshold` nil, `enable-local-variables` :safe, `enable-dir-local-variables` nil, `find-file-hook` nil, `inhibit-message` t. Wrap the `call-interactively` inside `jetpacs-buffer-call-shimmed` **and** the one inside `jetpacs-buffer-invoke-at` (the generic `emacs.buffer.act` path reaches the same `compile-goto-error`, and it is *not* shimmed). Also promote `jetpacs-buffer--scalar-text` (`jetpacs-buffer.el:327`) to public `jetpacs-buffer-scalar-text` — JC-2 is its second consumer.

---

## 3. `emacs/jetpacs-tablist.el` — public API, dependency order

Requires `cl-lib subr-x tabulated-list jetpacs-widgets jetpacs-surfaces jetpacs-buffer`. `tabulated-list` is required even though the walk scrapes the printed buffer: `--sort-chips`, `entry-col` and both handlers read `tabulated-list-format` / `-sort-key` and call `tabulated-list-print`.

| # | Definition | Contract | Status |
|---|---|---|---|
| 1 | `(defcustom jetpacs-tablist-max-rows 100 …)` | Row cap; excess reported by a trailing caption. A **line** cap only — it does not bound §4.5 bytes. | done |
| 2 | `(defvar jetpacs-tablist-view-buffer-function (lambda (name) …))` | Host seam navigating the Companion to a named buffer. **Zero in-file callers.** Decision 8. | done |
| 3 | `(defvar jetpacs-tablist-header-functions nil)` | Alist `(MODE . FN)`; FN of BUF returns a **LIST** of nodes (spliced by `append`), placed between the title row and the chips. | done |
| 4 | `(defvar jetpacs-tablist-row-functions nil)` | Alist `(MODE . FN)`; FN of `(ID ENTRY POS)` returns one row node or nil. Called with the list buffer current. **Contract addition [OPEN]:** a skin that emits its own `emacs.buffer.act` descriptor MUST expose its own POS, and MUST NOT put an entry ID (an arbitrary Lisp object — `package-desc`, a live process, a marker) into `:args`. | **[OPEN]** (docs + walk fix) |
| 5 | `(defvar jetpacs-tablist-filter-functions nil)` | Alist `(MODE . FN)`; FN of `(ID ENTRY)` keeps a row. Runs **before** the cap, so cost is O(buffer lines). | done |
| 6 | `(defun jetpacs-tablist--mode-fn (alist))` | First ALIST entry whose MODE the buffer derives from. **Docstring lies:** it says "nearest derived mode wins"; the body is first-match-in-alist-order, and `setf (alist-get …)` prepends, so **last registered wins**. Decision 9. | **[OPEN]** |
| 7 | `(defun jetpacs-tablist--rows ())` | `(POS ID ENTRY)` per printed row of the current buffer. POS is bol; ID/ENTRY from `tabulated-list-get-id`/`-get-entry` (`defsubst`s over `get-text-property`, `tabulated-list.el:185/191`). The `(and id entry)` guard skips the fake header **and**, in 30.1, `tabulated-list-groups` title lines (`tabulated-list.el:494` inserts a bare `(insert (car group) ?\n)`). Decision 10. | done |
| 8 | `(defun jetpacs-tablist-col-string (col))` | Display string of one column descriptor. **[OPEN]** add `((eq (car col) 'image) " ")` **before** the `consp` branch — Emacs renders an image descriptor as a single space (`tabulated-list-print-col`, `tabulated-list.el:596`), this yields the literal `"image"`. **[OPEN]** route the result through `jetpacs-buffer-scalar-text` (§4.1). | **[OPEN]** |
| 9 | `(defun jetpacs-tablist-entry-col (entry name))` | ENTRY's column named NAME per the buffer's own format, or nil. Public skin API; must be called with the list buffer current. | done |
| 10 | `(defun jetpacs-tablist--sort-chips ())` | Flow row of chips over sortable columns (`(nth 2 col)`), active one arrow-labelled and `:selected t`. Returns nil when `chip` or `flow_row` is unadvertised (sorting is chrome). `:selected` uses `t`/`:json-false` (`jetpacs--check-bool` accepts nothing else). **[OPEN]** carry `:desc` in the descriptor (Decision 7). | partial |
| 11 | `(defun jetpacs-tablist--default-row (buf-name pos entry))` | Generic row card: first column as `:style "label"`, the rest joined `"  ·  "` as `:style "caption"`; whole card taps `emacs.buffer.act`. Calls `jetpacs-buffer-expose`. Degrades `card`→`column`+`button`. | done |
| 12 | `(defun jetpacs-tablist-render (buf))` | Returns a LIST of nodes. `jetpacs-buffer-forget-exposed` **before** the rows. **[OPEN]** move the `jetpacs-buffer-expose` call out of `--default-row` and into the render walk, so a `row-fn` skin's rows are exposed too; **[OPEN]** budget participation. | partial |
| 13 | `(defun jetpacs-tablist--refresh-view (params))` | `(funcall jetpacs-buffer-refresh-function (plist-get params :surface))`. **HARD ARITY BREAK vs poc:** the seam was nullary in poc-v1; JC-1 calls it with the originating surface (`jetpacs-buffer.el:852-858`), and it is wired to `jetpacs-shell-push` whose first positional is SURFACE-OR-OWNER. A zero-arg call inside a dispatch extent resolves to `app:main`. **[OPEN]** defer via `run-at-time 0` to match `jetpacs-buffer--defer-refresh`. | partial |
| 14 | `(defun jetpacs-tablist--buffer-arg (args))` | The live `tabulated-list-mode` buffer named by `:buffer`, or nil. **[OPEN]** add the second §23.1 gate: the buffer must appear in `jetpacs-buffer-exposed` (Decision 1). | **[OPEN]** |
| 15 | `(jetpacs-render-buffer-register 'tabulated-list-mode #'jetpacs-tablist-render)` | Broadest possible registration; precedence is load order. | done |
| 16-17 | `(jetpacs-defaction "tablist.sort" …)`, `(jetpacs-defaction "tablist.refresh" …)` | §5. | partial |

---

## 4. Drift table — poc-form → format-6 form

Every call site that changes. All verified against `jetpacs-widgets.el`.

| Site | poc-v1 | format-6 | Why |
|---|---|---|---|
| `results--card` L169-172; `tablist-render` L149 | `(jetpacs-box (list N) :weight 1)` | `(jetpacs-with-attrs (jetpacs-box N) :weight 1)` | `:weight` is a §16.5 **universal** attr; `jetpacs-box` reads only `:alignment`/`:on-tap` (`jetpacs-widgets.el:714`) and **silently drops** it — the row layout collapses with no error. `jetpacs-with-attrs` errors on a non-universal key (`:352`). |
| `results--card` L174-175 | ``:args `((buffer . ,name) (pos . ,pos))`` | `:args (list :buffer name :pos pos)` | `jetpacs-action` requires `(and (consp args) (keywordp (car args)))` (`:456`); an alist's car is a cons → build-time error. |
| `tablist--sort-chips` L113, `--default-row` L129, `-render` L153 | alist `:args` | `(list :buffer … :column …)` / `(list :buffer …)` | same |
| `results--card` L176; `buffer-view-actions` L396,L402; `tablist` ×3 | `:when-offline "drop"` | omit | `drop` is now the builder default (was `queue`); the explicit member is legal but emits `when_offline` on up to 300 descriptors and changes golden bytes. |
| `results-render` L194-196, L199-201; `tablist--default-row` L125,L127; `-render` L149,L167 | `(jetpacs-text S 'caption)` / `'label` | `(jetpacs-text S :style "caption")` / `:style "label"` | `:style` is a keyword taking a **string** from `jetpacs--text-styles` (`:218`); an unknown style **signals** at build time (unlike the wire, where it falls back to body). |
| `buffer-view-actions` L395,L401 | `:args '((dir . -1))` | `:args (list :dir -1)` | plist, and freshly consed — not a shared quoted literal. |
| `results.visit` handler L322-325 | `(lambda (args _))` + `(alist-get 'buffer args)` | `(lambda (args params))` + `(plist-get args :buffer)` | jsonrpc decodes with `:object-type 'plist`. PARAMS is now load-bearing (`:surface`, `:revision_seen`). |
| `results.step` L347-349 | `(alist-get 'dir args)` | `(plist-get args :dir)`, validated `(memq dir '(1 -1))` | poc accepted any `numberp`: a float wedges `nth` with `wrong-type-argument`; `dir` 500 steps 500 hits. |
| `tablist` handlers L180,L196 | `(get-buffer (or (alist-get 'buffer args) ""))` | explicit `(and (stringp name) (get-buffer name))` | absent `:args`, `{}` and `null` all collapse to nil under `plist-get`. |
| all handler bodies, every failure path | `(message "…")` + implicit nil | an explicit `accepted`/`stale`/`rejected` symbol | `jetpacs--dispatch` (`jetpacs-surfaces.el:232-241`) `pcase`-matches exactly those three; anything else answers `rejected` **and** fires `display-warning :error` (decision Q3). Never `duplicate`. |
| `tablist-refresh-view` L174-176 | `(funcall jetpacs-buffer-refresh-function)` | `(funcall jetpacs-buffer-refresh-function (plist-get params :surface))` | arity changed in JC-1; zero-arg pushes `app:main` under D1. |
| `results--follow` L236 | `(jetpacs-buffer-call-shimmed cmd)` | same call, **plus** an ON-ERROR thunk and the prompt-refusing wrapper | signature is `(cmd &optional on-error)` in llm-poc-2 — compiles unchanged, but the shim swallows errors and always returns a cons. |
| `results--index-of` L259 | `(or (cl-position …) 0)` | `(cl-position …)` — nil on miss | 0-on-miss turns an unknown offset into "visit the first hit" and answers `accepted`. |
| `results--card`/`--loci`, `tablist-col-string` | raw `buffer-substring-no-properties` / `(format "%s" col)` into a node | wrap in `jetpacs-buffer-scalar-text` | §4.1 / JC-1 audit IMPL 5: raw-byte chars `#x3FFF80..#x3FFFFF` make `json-serialize` signal `wrong-type-argument`, taking down the push. |
| `results-render` / `tablist-render` card paths | unconditional `card`/`rich_text`/`icon`/`chip`/`flow_row`/`icon_button` | gate each with `jetpacs-node-advertised-p` and degrade (§6) | GATE 1 in `jetpacs-shell--gate-spec` **signals** — it never sanitizes — so one unadvertised type refuses the whole push. |
| `--buffer-p` L112 | `(apply #'derived-mode-p jetpacs-results-modes)` | `(derived-mode-p jetpacs-results-modes)` | 30.1 deprecates the `&rest` convention, not the list one (`subr.el:2849`). |
| `jetpacs-defaction` call shape | poc `(name fn &key args doc)` | `(name fn)` — a plain defun | extra arguments are a `wrong-number-of-arguments` error at load. Name must contain a dot and pass the §4.4 charset. |
| file header | "Tier 0.5" framing | rung JC-2 of `PLAN-jetpacs-consumers.md`; `:group 'jetpacs` resolves at `jetpacs-surfaces.el:36`; `setopt` in docs (30.1 floor) | — |
| `jetpacs-table-row` `(KIND &rest cells)` | — | **non-event**: neither module emits a `table` node. | — |

---

## 5. The actions

Handler contract (`jetpacs-surfaces.el:209-293`): `(lambda (ARGS PARAMS) …) => 'accepted | 'stale | 'rejected`. ARGS is the `:args` plist; PARAMS is the full `event.action` plist. The return value **is** the reply. `error`/`quit` → `rejected` (logged with the error **symbol** only, amendment #74); a deliberate `jsonrpc-error` (1500 event-retry) is re-signalled and reaches the endpoint. `rejected` is **permanent** — the Companion deletes its durable record — so a transient failure must be `stale`, not `rejected`.

Follow JC-1's template order (`jetpacs-buffer--tap-status`, `jetpacs-buffer.el:874-897`): **14.1 arg-resolution → 14.5 staleness → 23.1 exposure → synchronous effect → deferred re-push → `accepted`**. **[OPEN]** the draft's `results.visit` checks exposure *before* staleness, which gives a lagging-but-legitimate tap a terminal `rejected` where `stale` (re-presentable) is correct.

### 5.1 `results.visit`

**Descriptor (build side, `jetpacs-results--card`):**
`(jetpacs-action "results.visit" :args (list :buffer NAME :pos POS))` — `when_offline` omitted (default `drop`). File-locus producers build `:args (list :index I)`.

**Handler sketch:**

```elisp
(lambda (args params)
  (let ((buf-name (plist-get args :buffer))
        (pos      (plist-get args :pos))
        (index    (plist-get args :index))
        (jetpacs-results--event-surface (plist-get params :surface)))
    (cond
     ((and (stringp buf-name) (integerp pos))          ; buffer branch
      (let ((buf (get-buffer buf-name)))
        (cond
         ((not (jetpacs-results--buffer-p buf))                    'rejected)
         ((jetpacs-event-stale-p params)                           'stale)
         ((not (jetpacs-buffer-exposed-p buf-name pos "results.visit")) 'rejected)
         (t (let* ((loci (jetpacs-results--loci buf))              ; capped
                   (i (and loci (jetpacs-results--index-of loci pos))))
              (cond ((null loci) 'stale)
                    ((null i)    'stale)
                    ((jetpacs-results--goto-buffer buf loci i) 'accepted)
                    (t 'rejected)))))))
     ((integerp index)                                  ; file branch
      (let ((set jetpacs-results--file-set))
        (cond
         ((jetpacs-event-stale-p params)                            'stale)   ; [OPEN]
         ((not (jetpacs-results--file-set-current-p params))        'stale)   ; [OPEN] generation
         ((not (and set (>= index 0) (< index (length set))))       'stale)
         ((jetpacs-results--goto-file set index)                    'accepted)
         (t 'rejected))))
     (t 'rejected))))
```

| Branch | Status | SPEC rule |
|---|---|---|
| `:buffer` not a string / `:pos` not an integer / neither shape present | `rejected` | §14.1 — permanently invalid arguments |
| no such buffer, or not in `jetpacs-results-modes` | `rejected` | §23.1 — wire-supplied name outside the allowlist |
| `jetpacs-event-stale-p` | `stale` | §14.5 — the card indexes into the snapshot it was tapped against; `jetpacs-surfaces.el:309-318` names exactly this case |
| offset not in the exposure table | `rejected` + log | §23.1 — "an offset never rendered" |
| rescan yields no loci, or POS resolves to no locus | `stale` | §14.5 — a re-run grep moved the row; the poc silently visited row 0 and answered success |
| the follow produced no destination (target file gone) | `rejected` | §14.1 — re-presenting cannot fix it |
| jump landed and the seam was invoked | `accepted` | §14.4 — the effect is complete; **not** a volatile-callback accept (JC-1 audit IMPL 4) |
| `:index` out of range / no active set / set generation changed | `stale` | §14.5 |

**§23.1 validation:** reuses **JC-1's exposure table** (`jetpacs-buffer-expose` / `-exposed-p`, `jetpacs-buffer.el:242-269`) — the same table `emacs.buffer.act` consults — **plus** the mode allowlist as an independent second gate. **[OPEN, P2]** the table is a single namespace: after a results render, `{"action":"emacs.buffer.act","args":{"buffer":"*grep*","pos":<locus>}}` passes every gate and reaches `jetpacs-buffer-invoke-at`, which `call-interactively`s the row's RET binding with **no display shim** — popping a desktop window and reaching the same prompt. One expose record authorizes two actions with different safety envelopes. See Decision 1.

**D2 blocking risk — P1, three independent wedges, all inside the dispatch extent:**

1. `--follow` → `compile-goto-error` → `compilation-find-file` prompts `read-file-name` **inside a `while (null buffer)` loop** — verified `emacs-30.1:lisp/progmodes/compile.el:3275` ("Repeat until the user selects an existing file") and `:3286`. Reached by an *ordinary* tap on stale grep output after a `git checkout`. `jetpacs--dispatch` pins `read-file-name-function` to the default (`jetpacs-surfaces.el:228`), which makes the prompt *more* likely to reach a real minibuffer, not less. On a headless daemon nobody answers: the filter never returns, no reply is sent, the session dies on timeout. **The draft's commentary at `jetpacs-results.el:347-348` asserts the opposite** ("Neither prompts, so neither blocks the dispatch extent (decision D2)") — delete that claim.
2. `--file-dest` → `find-file-noselect` can block on the large-file `y-or-n-p` (`abort-if-file-too-large`, `files.el:2454` → `files--ask-user-about-large-file`, `:2441`), the unsafe-file-local-variables confirm, an epa passphrase for a `.gpg` path, TRAMP auth/network, or arbitrary `find-file-hook` code. Its `condition-case … (error nil)` catches **none** of them: prompts are not errors. Also refuse `(file-remote-p file)` outright.
3. `--loci` rescans the entire results buffer on every visit **and** every step — unbounded local work on a 300k-line `*compilation*`.

**Mitigation:** wrap both primitives in `jetpacs-buffer-with-no-prompts` (§2) so a prompt becomes an error → `rejected`; cap the `--loci` scan. **Do NOT** "fix" this by deferring the effect to `run-at-time 0` and returning `accepted` — that is the non-conforming construction §14.4 names and JC-1 audit IMPL 4 flags. The effect stays synchronous (bounded local work is permitted under D2); only the re-push may defer. The surface push itself is not a blocking risk: ebp uses only `jsonrpc-notify` / `jsonrpc-async-request`.

### 5.2 `results.step`

**Descriptor:** `(jetpacs-action "results.step" :args (list :dir 1))` / `(list :dir -1)`. **[OPEN]** add `:from I` — the index the chrome was rendered against.

**Handler sketch:** read `dir`; look up the nav **for `(plist-get params :surface)`**; `target = (+ (plist-get nav :index) dir)`; `pcase` on `:kind` — `buffer` re-`get-buffer`s, re-checks `--buffer-p`, rescans `--loci` (so a reverted buffer steps sanely) and calls `--goto-buffer`; `file` steps over the `:loci` snapshot armed at visit time via `--goto-file`.

| Branch | Status | SPEC rule |
|---|---|---|
| `:dir` absent, not an integer, or not in `{1,-1}` | `rejected` | §14.1 |
| no nav armed for this surface | `stale` | §14.5 — the chrome was legitimately offered; the context is gone |
| `:from` ≠ the armed `:index` | `stale` | §14.5 — a replayed/duplicated descriptor |
| results buffer killed or no longer a results mode | disarm, `stale` | §14.5 |
| loci now empty, or `target` out of range | `stale` | §14.5 — the chrome only ever offers the in-range direction, so out-of-range means the set changed |
| `jetpacs-event-stale-p` | `stale` | §14.5 |
| the new locus is shown | `accepted` | §14.4 |
| unknown `:kind` | `rejected` | §14.1 |

**§23.1 validation:** the descriptor carries **no identity of the result set** — its entire meaning is process-global `--nav`. There is no offset off the wire, so the exposure table does not apply; `when_offline: drop` (the format-6 default) is the load-bearing mitigation and **must be kept**. Carrying `:from I` and rejecting a mismatch makes that explicit rather than incidental. Blocking risk is identical to `results.visit` — same `--follow` / `--file-dest` primitives, plus a full rescan per step.

### 5.3 `tablist.sort`

**Descriptor:** `(jetpacs-action "tablist.sort" :args (list :buffer NAME :column COL :desc BOOL))` — `:desc` **[OPEN]**, built from the chip's own rendered arrow.

**Handler sketch:** resolve the buffer through `--buffer-arg` (mode gate + exposure gate); find COL in **that buffer's own** `tabulated-list-format`; check `(nth 2 col)` sortable; `(setq tabulated-list-sort-key (cons col desc))`; `(tabulated-list-print t)`; defer the re-push; `accepted`.

| Branch | Status | SPEC rule |
|---|---|---|
| `:buffer` not a string / no live buffer / not `tabulated-list-mode`-derived | `rejected` | §14.1 + §23.1 |
| buffer never rendered to this Companion **[OPEN]** | `rejected` | §23.1 — audit IMPL 2, one level up (offset → whole buffer) |
| `:column` not a string, or names no column of that format | `rejected` | §23.1 |
| column not sortable (`(nth 2 col)` nil) **[OPEN]** | `rejected` | §14.1 — `tabulated-list--get-sorter` returns nil for an unsortable column and, with a non-nil FLIP, wraps it as `(lambda (a b) (funcall sorter b a))` → **`void-function nil` inside `tabulated-list-print`** (verified `tabulated-list.el:412-431`). The chips only *offer* sortable columns; the handler must not trust the chip set. |
| `tabulated-list-print` returned | `accepted` | §14.4 — the sort is durable in the buffer before the reply leaves |
| a signal from `tabulated-list-print` | `rejected` (via the shim) | §14.4 |
| staleness | **not consulted** | column names are revision-stable; document the choice |

**D2:** `tabulated-list-print` **re-evaluates** `tabulated-list-entries` when it is a function (verified `tabulated-list.el:460-467`) — a mode whose entry generator shells out or hits the network blocks the dispatch extent. Bounded for package-menu/process-menu/bookmark/timer-list; document the exposure.

**Idempotence [OPEN, §14.4/§14.5]:** the poc's flip (`(and (equal (car sort-key) col) (not (cdr sort-key)))`) makes the direction a function of the **current** key, not of what the user saw. A second tap racing a re-sort flips the opposite way from what the chip promised. Carrying `:desc` from the rendered chip removes the snapshot dependence entirely and is strictly better than adding a `stale` gate.

### 5.4 `tablist.refresh`

**Descriptor:** `(jetpacs-action "tablist.refresh" :args (list :buffer NAME))`.

| Branch | Status | SPEC rule |
|---|---|---|
| `:buffer` unresolvable / not `tabulated-list-mode`-derived | `rejected` | §14.1 + §23.1 |
| buffer never rendered to this Companion **[OPEN]** | `rejected` | §23.1 |
| `revert-buffer-function` is not `tabulated-list-revert` **[OPEN]** | `rejected` | D2 / §4.6 — see below |
| the revert signalled | `rejected` | §14.4 — the draft's `ignore-errors` + unconditional `accepted` is a false accept |
| the revert completed | `accepted` | §14.4 |
| staleness | **not derivable** — do **not** consult `jetpacs-event-stale-p` | refresh is idempotent and revision-independent |

**D2 — P1, the worst exposure in either module.** `revert-buffer` dispatches the buffer's own `revert-buffer-function`. `tabulated-list-mode` installs the benign `tabulated-list-revert`, but derivatives override: `package-menu-mode` sets it to `package-menu--refresh-contents` (verified `package.el:3238` → `:3680-3691`), which calls `(package-refresh-contents package-menu-async)` — archive downloads, and `package-import-keyring` → `epg-wait-for-completion`'s `accept-process-output` loop, which **re-enters the process filter** inside the dispatch extent. `(revert-buffer nil t)` does **not** fix this: package-menu's own docstring says the ARG and NOCONFIRM arguments "are ignored". The poc header names the package menu as the first consumer. **The allowlist is mandatory**, in the same shape as `jetpacs-buffer-fold-commands` (`jetpacs-buffer.el:291-299`), which exists precisely so "the phone can never trigger an arbitrary command". Anything outside it is honestly `rejected` — deferring to `run-at-time 0` and answering `accepted` is forbidden by §14.4 without a durable work item.

---

## 6. Node-type risk (§16.2)

The Core Node Set is exactly `text row column box spacer divider button text_input`. Everything else is OPTIONAL and **MUST** appear in `surface_profiles.app.node_types` before emission. GATE 1 in `jetpacs-shell--gate-spec` **signals** (never sanitizes), and the gate is deliberately outside the degrade `condition-case`, so one unadvertised type refuses the **entire** push — §13.2 then leaves the old snapshot and only a `message` is logged. The reference Companion advertises all of these (`NodeSupport.kt:28-34`), so a naive port passes every local smoke and fails only in the field. Gate helper: `(jetpacs-node-advertised-p TYPE &optional TARGET)` (`jetpacs-surfaces.el:329`), which assumes the rich form when no client is attached (offline renders, tests).

| Optional type | Emitted by | Fallback when unadvertised |
|---|---|---|
| `card` | `results--card`, `tablist--default-row` | `column` of the body + a Core `button` carrying the same descriptor (keeps the row **visible and tappable**) |
| `rich_text` | `results--card` | `(jetpacs-text label :style "mono")` — mirrors JC-1's `jetpacs-buffer--spans->text` |
| `icon` | `results--card` chevron | omit the chevron, emit the body alone |
| `icon_button` | `tablist-render` refresh, `results-buffer-view-actions` | `(jetpacs-button "Refresh" …)` / `"Previous"` / `"Next"` |
| `chip` + `flow_row` | `tablist--sort-chips` | return nil — sorting is chrome; a Core-only Companion is better served by the rows |
| `lazy_column` | not emitted today | — but note the JC audit's finding that the reference Companion honours `:scroll_here` only for **direct children of `lazy_column`**, which bounds what the region view can promise |

The no-loci fallback path (`jetpacs-buffer-render`) already degrades internally — `--render-region` computes `rich-ok` from the same helper.

---

## 7. Exit gate — checklist

Plan JC-2 gate: *pure-helper ERT (locus parse); render structural ERT (cards + `results.visit` `:args` plist + cap note); action round-trip against a stubbed visit seam (armed stepper, boundary clamps); live smoke on `occur`/`grep`.* Existing suite: `test/jetpacs-results-test.el`, driven by `test/run-tests.sh` (which already byte-compiles both modules under `byte-compile-error-on-warn` and runs the suite).

**Already green**

- [x] `jetpacs-results-locus-parse` — hand-applied text properties, no occur/grep run needed
- [x] `jetpacs-results-buffer-p-gates-mode`
- [x] `jetpacs-results-render-structure` — cards, `:args` plist, `results.visit`
- [x] `jetpacs-results-render-cap-note`
- [x] `jetpacs-results-render-degrades-to-core` / `jetpacs-tablist-render-degrades-to-core` (Core-only profile fixture)
- [x] `jetpacs-results-empty-falls-back-to-tier0`
- [x] `jetpacs-results-visit-statuses`, `-visit-moved-row-is-stale`, `-visit-file-loci`
- [x] `jetpacs-results-step-boundaries`, `-step-chrome`
- [x] `jetpacs-tablist-render-structure` (incl. an `jetpacs-buffer-exposed-p` assertion), `-action-statuses` (incl. the surface the re-push targeted)
- [x] byte-compile guard covers `jetpacs-results` + `jetpacs-tablist`

**Must be added before the rung closes**

- [ ] **Prompt refusal (P1).** Fixture: a `compilation-mode` buffer whose locus keymap binds a command calling `read-file-name` (and one calling `y-or-n-p`). Assert the handler returns `rejected` **and returns at all** — no hang.
- [ ] **§4.1 raw bytes.** A results buffer and a tabulated-list entry containing `\310\311`; assert `jetpacs-node->canonical-json` of the render succeeds.
- [ ] **Unsortable column.** `tablist.sort` on a `(nth 2 col)`-nil column → `rejected`, no `void-function nil`.
- [ ] **Unrendered buffer.** `tablist.sort` / `tablist.refresh` against a live tabulated-list buffer never rendered → `rejected`.
- [ ] **Revert allowlist.** A buffer whose `revert-buffer-function` is not `tabulated-list-revert` → `rejected`, and the function is never called.
- [ ] **§4.5 budget.** A wide/long fixture that exceeds `max_frame_bytes`; assert the card walk stops with a truncation caption rather than over-emitting.
- [ ] **Cross-action exposure scoping** (if Decision 1 = scope): `emacs.buffer.act` at a results locus → `rejected`.
- [ ] **Golden bytes** (plan §5A): both renders serialized into `test/goldens/renderers.golden`; today the tests assert structurally only.
- [ ] **`(jetpacs-check-profile tree 'app)`** in addition to the live-set `jetpacs-check-node-types` already asserted.
- [ ] **Per-surface nav** (if Decision 2 = key by surface): two owners, interleaved visits, assert each `results.step` walks its own set.
- [ ] **`:from` echo** (if Decision 6): a replayed step descriptor → `stale`.
- [ ] **Live smoke.** `test/smoke-results.el` exists and drives a real `occur` → cards → tap → region view → Next; needs an actual device run (`adb forward tcp:8765 tcp:8765`). Add a tablist smoke (`list-timers` / `list-processes`) covering sort + refresh.

---

## 8. Risks / open questions — decisions for a human

**1. Exposure-record scope (§23.1).** JC-1's table is keyed `(BUFFER . POS)` and consulted by `jetpacs-buffer--tap-status` for *every* action. A results locus therefore also authorizes `emacs.buffer.act`, which runs the same goto command **unshimmed** through `jetpacs-buffer-invoke-at` — popping a desktop window and reaching `compilation-find-file`'s prompt loop. Options: (a) add an ACTION argument to `jetpacs-buffer-expose`/`-exposed-p` so a record authorizes one verb; (b) leave shared and accept the second path. **Recommend (a)** — cheap, and it keeps the JC-1 gate honest as more skins register. Also add a `jetpacs-buffer-exposed-buffer-p` predicate for the whole-buffer verbs (`tablist.sort`/`refresh`).

**2. Per-owner stepper state (D1).** `--nav` and `--file-set` are single process-global slots, but surfaces are per-owner `app:<owner>`. Owner B's visit silently re-arms owner A's chrome, and `buffer-view-actions` can attach step buttons to the wrong app's top bar. Options: (a) `equal` hash keyed on the event's `:surface` (render time: `(jetpacs--default-surface)`); (b) document the single-slot limit. **Recommend (a)** — it is the same correction D1 already forced on `jetpacs-async--flush-push` and `jetpacs-shell-define-root`, and (b) becomes a real bug the moment a second app renders results.

**3. File-set staleness (P1, §14.5).** The file branch validates only the index range against a global slot any producer overwrites wholesale. Run a search, tap result 3, and if a second search replaced the set before the event lands, index 3 of the **new** set is a different file — opened, `accepted`, no diagnostic. Options: (a) call `jetpacs-event-stale-p` in the file branch; (b) stamp the set with a generation in `set-file-loci` and refuse an event whose descriptor predates it; (c) both. **Recommend (c)** — (a) alone is nil until the first confirmed push and nil for dialog events; (b) decides staleness by the set's own identity.

**4. Does `jetpacs-results.el` require `jetpacs-shell`?** The draft does, solely so `jetpacs-results-show-region` can call `jetpacs-shell-push`. That breaks the layering the poc modules respected (buffer↔shell is a one-way seam installed by `jetpacs-shell.el:612`). Options: (a) keep the require; (b) re-push through `(funcall jetpacs-buffer-refresh-function SURFACE)` — the same seam JC-1 uses, already wired to `jetpacs-shell-push`, and it drops the require entirely. **Recommend (b).**

**5. Synchronous vs deferred re-push.** `--show` funcalls the seam inside the dispatch extent, and `jetpacs-shell-push` **signals** on any gate failure — which would escape *after* the jump landed, answering `rejected` and leaving `--nav` armed at a view that never opened. Options: (a) `condition-case` the seam funcall only; (b) `condition-case` **and** defer the push via `run-at-time 0`, matching `jetpacs-buffer--defer-refresh`. **Recommend (b)** — effect synchronous (so `accepted` is honest), push deferred, one discipline across JC-1 and JC-2.

**6. `results.step` identity.** The descriptor carries nothing but a direction; its meaning is whatever is armed when it arrives. Options: (a) rely on `when_offline: drop`; (b) echo `:from I` and answer `stale` on mismatch. **Recommend (b)** — makes the invariant explicit rather than incidental, and it is one integer.

**7. `tablist.sort` direction.** Options: (a) keep the flip (snapshot-dependent, non-idempotent); (b) carry `:desc` from the rendered chip and set the key verbatim. **Recommend (b)** — removes the §14.5 dependence entirely and makes the action idempotent per §14.4.

**8. `jetpacs-tablist-view-buffer-function`.** Zero in-file callers; every consumer is out of the JC manifest. Options: (a) keep as an unwired seam (cheap, documents the contract); (b) defer to the rung that ports a consumer. **Recommend (a)**, with the `jetpacs:` (lowercase) prefix the rest of llm-poc-2 uses.

**9. Skin precedence.** `jetpacs-tablist--mode-fn`'s docstring promises "nearest derived mode wins"; the body is first-match-in-alist-order and `setf (alist-get …)` prepends, so **last registered wins**. `jetpacs-render-buffer` has the identical shape. Options: (a) rank by `derived-mode-all-parents` depth (exists in 30.1, `subr.el:2782`); (b) fix the docstrings to state the real rule. **Recommend (a) for `--mode-fn`** (three small alists, cheap) **and (b) for the render registry** (changing global dispatch precedence is a JC-1 decision, not this rung's).

**10. `tabulated-list-groups` (new in 30.1).** Group titles are inserted as bare lines carrying no `tabulated-list-id`/`-entry` (`tabulated-list.el:494`), so the `(and id entry)` guard silently discards them and a grouped list renders as one flat card stream. Options: (a) accept and document; (b) detect the group lines and emit `section_header`/`text` separators. **Recommend (a) for JC-2**, filed for the rung that first ports a grouping mode.

**11. Counter vs cap.** `--render` caps cards at `jetpacs-results-max-loci` but `--goto-buffer`/`--show` record `:count (length loci)` **uncapped**, so the stepper reports "5/1200" and can walk into loci that were never rendered (and never exposed). Options: (a) cap the `--loci` scan so the counter matches the cards; (b) document that the stepper deliberately outruns the list. **Recommend (a)** — it also fixes the D2 unbounded-scan risk in one change.

**12. Budget participation (§4.5).** Neither renderer touches `jetpacs-buffer--budgets` / `jetpacs-buffer-with-budget` / `--node-bytes`; 300 cards × (card+row+box+rich_text+icon) ≈ 1500 nodes and 300 spans, each carrying a whole trimmed source line (kilobytes over minified code). Options: (a) share the JC-1 budget, spending `--node-bytes` per card and stopping with the same truncation caption; (b) clamp the per-card label length only; (c) justify the 300/100 caps against the smallest conforming limit. **Recommend (a)+(b)** — the reference Companion advertises no `max_rich_spans` at all, so the byte half is the one that bites.

**13. Card identity (§16.1).** No card carries a `key`, so identity is tree-path index — and a results buffer is exactly the thing that gets re-run and re-ordered. Harmless for today's stateless cards; a `row-fn` skin returning a `collapsible` would have its expansion state reassigned on every sort. **Recommend** giving each card a `(jetpacs-with-attrs card :key …)` now, derived from the locus index / the entry's first column, sanitized to a §4.4 identifier (`:key` is validated; `:args` is opaque and needs no sanitizing).

**14. Seam has no other end yet.** `jetpacs-results-visit-region-function` and `jetpacs-results-buffer-view-actions` are called by nothing else in llm-poc-2, so without the draft's `show-region`/`region-nodes` default they read as dead code. The ERT must exercise both seams (armed nav, both boundary ends, dest mismatch, dead source) or the rung ships untested surface area.