# Plan: JA-6 audit — five P1 fixes in jetpacs-files.el + regression tests

Repo: `/home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-2` (worktree branch `claude/llm-poc-2-room3-nav3-bb70f6`).
Files touched: `emacs/jetpacs-files.el`, `test/jetpacs-files-test.el`. No commits.

Baseline verified: 45/45 tests pass; `jetpacs-files.el` byte-compiles clean under
`byte-compile-error-on-warn`. Authoritative spec: `docs/AUDIT-ja6-2026-07-28.md` lines 52–243.

Facts verified against Emacs 30.1 source (`~/pkb/resources/emacs/emacs`, tag `emacs-30.1`):
- `file-in-directory-p` truenames FILE internally → literal containment must be checked via
  the *parent's* truename, never by handing the literal to a truenaming check.
- `delete-directory` with RECURSIVE t on a symlink skips recursion and calls
  `delete-directory-internal` (rmdir) wrapped in `files--force t` → **silently no-ops** on a
  link. The explicit `(file-symlink-p act) → (delete-file act)` leg is mandatory.
- `rename-file` renames the link itself (rename(2); cross-device fallback preserves links).
  `copy-file` follows the link (copies content) — that native behavior gets pinned.
- Runtime probe confirmed: a dir named with raw byte 255 is creatable/accessible here, and
  both `file-truename` and dired's `default-directory` preserve the raw-byte char. Gotcha:
  `(concat root (unibyte-string 255) "dir")` yields a **unibyte** string — tests must use the
  `file-truename` of it (multibyte, raw-byte char #x3FFFFF) so `jetpacs-files--wire-safe-p`'s
  char-class regexp sees it.

Current-code line anchors (drifted from audit): up-row :281, shared-row :357, grep scan cond
:548–570, grep read :484, edit-open :734, edit-screen :768, rename :854, move :882,
duplicate :910, menu handler :1066, delete handler :1088, save handler :1142 (buffer route
:1184, write-region :1190, edit re-stamp :1195).

---

## P1-1 — destructive ops act on the literal, guard checks both sides

**New helper** (in the F3 ops section, before `jetpacs-files--op-rename`):

```elisp
(defun jetpacs-files--check-op (path &optional require)
  "PATH validated for a DESTRUCTIVE op; returns the literal act path.
Containment is confirmed on BOTH sides: the full truename (via
`jetpacs-files--check', REQUIRE as given — the straddle rule) AND the
literal entry — the parent's truename plus the final component — so an
op can neither follow a link out of the sandbox nor unlink an
out-of-sandbox entry that points in.  The returned act path is the
exact directory entry delete/rename/copy touch; links are handled
natively (unlinked, relocated, content-copied), never followed."
  (jetpacs-files--check path require)
  (let* ((dfn (directory-file-name (expand-file-name path)))
         (parent (file-name-directory dfn)))
    (when (null parent)                 ; "/" — never an op target
      (signal 'jetpacs-path-refused (list 'outside-roots)))
    (concat (file-name-as-directory (jetpacs-files--check parent nil))
            (file-name-nondirectory dfn))))
```

Callers changed:
- **delete handler**: `(let ((act (jetpacs-files--check-op (plist-get args :path) nil))) ...)`;
  stale gate becomes `(not (or (file-symlink-p act) (file-exists-p act)))` (a dangling link is
  now deletable — it IS a directory entry); effect cond gains the symlink leg first:
  `((file-symlink-p act) (delete-file act))`, then dir → `delete-directory act t`, else
  `delete-file act`. Notify from `act`'s basename.
- **menu handler**: validate with `jetpacs-files--check-op` and pass the **act path** (not the
  truename) to `jetpacs-files--ops-menu-show`.
- **op-rename / op-move / op-duplicate**: each computes `(src (jetpacs-files--check-op path))`
  inside its existing `condition-case` (re-validation at act time; refusals reuse the pinned
  "<Op> refused: <symbol>" wording), then acts on `src`:
  rename target dir = `(file-name-directory src)`; move/rename via `(rename-file src target)`;
  duplicate via `(if (file-directory-p src) (copy-directory src target) (copy-file src target))`
  with `(jetpacs-files--duplicate-name src)`.
- Update the F3 section commentary + delete-handler comment to state the both-sides rule.

Known behavior deltas (justified, report them): deleting a root itself now refuses
(`outside-roots` on its parent — the sandbox no longer deletes its own boundary); a dangling
link whose target path lies outside the roots still refuses (truename containment); rename of
a dangling link refuses `unreadable` (default REQUIRE).

**Tests** (both fail pre-fix because pre-fix the *menu/delete handlers* hand the truename on):
1. `jetpacs-files-delete-unlinks-a-symlink-never-follows` — real dispatch. Fixture:
   `root/target/keep`, `root/link -> root/target`. Delete `:path root/link` → 'accepted, link
   gone, `target/keep` intact. Then: dangling link delete → 'accepted (pre-fix 'stale). Then
   the closed hole: outside dir with `outside/link2 -> root/f`; delete `:path outside/link2`
   → 'rejected + note "Delete refused: outside-roots", `root/f` intact (pre-fix deletes it).
2. `jetpacs-files-menu-ops-act-on-the-link-not-its-target` — real menu dispatch (granted
   `surfaces.dialog`, `ebp-client-dialog-show` captured, `jetpacs-flow-begin` run-inline,
   prompts stubbed, notify/push stubbed), one menu round per op:
   - rename `root/link` → "link2": `(file-symlink-p root/link2)` non-nil, target tree intact;
   - move `root/link` into `root/sub/`: `sub/link` is a symlink, target intact;
   - duplicate `root/flink -> root/f.txt`: `root/flink copy` is a **regular** file with the
     target's content (pins copy-file's native follow), `f.txt` untouched.

## P1-2 — capture the file's coding at open; write with it

- `jetpacs-files--edit-open`: capture `last-coding-system-used` right after
  `insert-file-contents` (set `coding`/`content` out of the temp buffer), store
  `:coding coding` in `jetpacs-files--edit` alongside `:seed`/`:mtime`.
- Save handler: around the (now sole, see P1-3) `write-region`, bind
  `(coding-system-for-write (and (equal (plist-get jetpacs-files--edit :path) true)
  (plist-get jetpacs-files--edit :coding)))` — stored value used only when the edit record is
  still current (path matches; the mtime gate already proved the file unchanged); nil keeps
  today's ambient behavior.
- The post-save edit re-stamp (:1195) carries `:coding` forward.

**Test** `jetpacs-files-save-round-trips-the-files-own-coding`: (a) fixture written with
`coding-system-for-write 'utf-8-dos`, content "line one\nline two\n"; `jetpacs-files--edit-open`
(push-screen stubbed) then real save dispatch with `:value` = seed and the record's mtime; raw
bytes via `insert-file-contents-literally` must equal "line one\r\nline two\r\n". (b) same with
`'iso-latin-1` and "café\n" → bytes `(unibyte-string ?c ?a ?f #xE9 ?\n)`. Both fail pre-fix
(CRLF→LF, é→UTF-8). Known consequence to report: a device edit introducing chars the stored
coding can't encode now degrades under that coding instead of silently flipping the file to
UTF-8 — the audit's prescribed contract.

## P1-3 — save never routes through `save-buffer`; refuse before mutating

- New cond leg after the stale gate:
  `((not (file-writable-p true)) (jetpacs-files--op-notify-refused "Save" 'unwritable surface) 'rejected)`
  — pinned layer wording "Save refused: unwritable".
- Replace the buffer route: ALWAYS `(write-region value nil true nil 'silent)` (coding-bound per
  P1-2). Only after it returns, if a visiting (already-unmodified) buffer exists:
  `(condition-case ... (with-current-buffer buf (revert-buffer :ignore-auto :noconfirm :preserve-modes)) (error (message ...)))`
  — revert re-reads, widens, updates the visited modtime, clears modified; a refresh failure
  must not flip a durable 'accepted. Update the route's commentary (the 30.1 erase-buffer note
  goes; the write-first invariant comes in).
- Existing narrowed-buffer save test (v3 whole: widened, unmodified, disk content) must keep
  passing through the new route.

**Test** `jetpacs-files-save-refuses-unwritable-before-any-mutation`:
`(skip-unless (not (zerop (user-uid))))`; file "keep\n" visited by `find-file-noselect`,
unmodified; `chmod 444`; real save dispatch with matching mtime, `:value "device\n"` →
'rejected, note "Save refused: unwritable", disk still "keep\n", buffer text "keep\n" and
`(buffer-modified-p)` nil. Unwind: chmod back, kill buffer. Fails pre-fix (buffer clobbered,
note "Save failed: …").

## P1-4 — non-regular files dropped before any read

- Grep scan cond (:548–570): insert `((not (file-regular-p path)) nil)` immediately ahead of
  the size leg (symlinks already dropped at the top; comment: FIFO/socket/device blocks in
  open(2) forever inside a non-yielding tick).
- `jetpacs-files--edit-open`: first eligibility leg `((not (file-regular-p true)) 'not-a-file)`,
  and route that reason to `(jetpacs-files--op-notify-refused "Open" 'not-a-file surface)` —
  NEVER to `jetpacs-files--read-fallback`, whose `find-file-noselect` blocks exactly the same way.

**Test** `jetpacs-files-grep-and-edit-open-drop-non-regular-files`:
`(skip-unless (executable-find "mkfifo"))`; `mkfifo root/pipe` (skip if it didn't produce a
non-regular file); `root/a.txt` = "needle\n". Hard-timeout shape (an in-process timer cannot
interrupt a blocked open(2), so regressions must *unblock then fail*): start two watchdog
subprocesses `sh -c "sleep 8; : > PIPE"` / `sleep 16` variant, killed in unwind. Scan via
`jetpacs-files--grep-start` with a wall-clock-bounded pump
(`while (and (not result) (< elapsed 5)) (accept-process-output nil 0.02)`); assert result
arrived AND elapsed < 5, hits = a.txt only. Then `jetpacs-files--edit-open` on the FIFO's
truename (stubs as in the eligibility test) → returns 'not-a-file, note
"Open refused: not-a-file", nothing navigated, no screen. Pre-fix: the scan blocks ~8s →
elapsed/result assertions fail instead of hanging.

## P1-5 — wire-safe gate at the remaining `:args` sites

- `jetpacs-files--up-row`: emit only `(when (and parent (jetpacs-files--wire-safe-p parent)) ...)`
  — no row at all (ceiling behavior); docstring gains the rule.
- `jetpacs-files--shared-row`: add `((jetpacs-files--wire-safe-p (directory-file-name shared)))`
  to the `and-let*`.
- `jetpacs-files--edit-open`: add `((not (jetpacs-files--wire-safe-p true)) 'unencodable)` as
  the second leg (after P1-4's non-regular leg — a wire-unsafe FIFO must hit 'not-a-file, not
  the buffer-host fallback; before oversize/desktop-modified — the editor can never host it
  regardless). Content check stays where it is. The edit screen (:768) is covered transitively:
  `jetpacs-files--edit` can no longer hold an unsafe path.

**Test** `jetpacs-files-wire-unsafe-paths-never-reach-args`: real on-disk fixture
`root/<255>dir/sub` via `(make-directory (concat root (unibyte-string 255) "dir/sub") t)`,
canonical bad path = its `file-truename` (multibyte raw-byte form — the banked trap: names
*listed* from disk decode, but our held string and dired's `default-directory` keep the raw
byte, verified by probe). Assertions:
(a) `(jetpacs-files--up-row bad-sub/)` → nil (pre-fix: a full row with raw `:args`);
(b) with `jetpacs-files--dir` = bad-sub, `(jetpacs-files--body)` is a "lazy_column" (proves the
real path rendered, not a degrade) and `(jetpacs-node->canonical-json body)` returns a string
(pre-fix: `json-serialize` signals wrong-type-argument on the up-row's raw `:dir`);
(c) shared-row: `jetpacs-files--shared-dir` bound to a raw-byte dir → row nil;
(d) `jetpacs-files--edit-open` on `root/<255>d/f.txt` ("plain\n") with stubs → 'unencodable,
read-fallback navigated once, no editor screen (pre-fix: editor pushed, returns nil).

---

## Execution order

1. Source edits P1-4 → P1-5 → P1-2 → P1-3 → P1-1 (independent regions; ops section last since
   it's the largest rewrite), keeping the file's dense-commentary style; update the module
   Commentary where it documents the now-enforced invariants (the `:args` rule already there;
   add the act-on-the-literal rule to the F3 section comment).
2. Append the six tests to `test/jetpacs-files-test.el` (new sections mirroring existing ones;
   fixtures pass roots slashless where prefix-containment matters — the with-tree macro's root
   is fine as-is since these tests don't probe prefix containment).
3. Sanity: temporarily revert each fix region in turn is NOT required — instead verify each new
   test fails against pre-fix code by running the new tests once against `git stash`-free…
   practical route: run the 6 new tests against a pristine checkout of jetpacs-files.el via
   `git show HEAD:emacs/jetpacs-files.el > scratch/pre.el` loaded with `-L` shadowing, OR
   simpler: write tests first, run against unmodified source, record the 6 failures, then apply
   fixes. (Chosen: tests-first failure run, then fix, then green run — gives the before/after
   counts the report needs.)
4. Gate: `emacs -Q --batch -L emacs -l test/jetpacs-files-test.el -f ert-run-tests-batch-and-exit`
   → 51/51; byte-compile `jetpacs-files.el` with `byte-compile-error-on-warn` → clean; delete .elc.
5. No `git commit`.

## Risks / fallbacks

- P1-5 (b): if dired's ls-decode mangles the raw-byte listing on some host, the body could
  degrade to empty_state and mask the pre-fix signal — the `"lazy_column"` assertion catches
  that; fallback is serializing `(jetpacs-files--dired-cards ...)` output directly.
- P1-4 pre-fix verification run will take ~8s (watchdog unblock) — expected, bounded.
- `revert-buffer` in batch: `:noconfirm` prevents prompts; failure path is condition-cased.
- The op tests drive the REAL dispatch/menu callback path per the audit's repros — direct op
  calls cannot distinguish pre/post fix for rename/move/duplicate (the substitution happens in
  the handlers), which is exactly why the pipeline route is mandatory.
