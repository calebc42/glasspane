# device/MANIFEST.md — the tablet re-provisioning bundle

> **Field note (2026-08-13, first live run):** the tree transport is now
> `tar` over the ssh exec channel, not rsync — Termux's rsync 3.5.0
> receiver hit an unexplained EACCES on chdir into a directory the same
> ssh login enters fine (no AVC, correct owner/modes). And pubkey auth
> is not assumed: Termux's openssh 10.5p1 accepted the ed25519 in the
> authorized_keys exchange yet denied the signed auth, so the kit keeps
> a generated password in `tools/onboard-scratch/` and serves it via
> `SSH_ASKPASS` whenever the key path fails.


What lands on the tablet, at which path, by which transport, and why.
This is the deploy contract `tools/onboard-tablet.sh` implements and
`tools/onboard-provision-remote.sh` finishes on the device side.

## Why a new bundle, next to `device/install.sh` + `device/init.el`

Those two files are the *existing*, working convention and this
manifest does not replace them — it describes a second transport for
the same elisp tree, because `install.sh`'s transport (`adb push` into
`/sdcard/Documents/jetpacs`) has two costs this bundle exists to avoid:

1. `/sdcard` needs `termux-setup-storage` (a permission dialog) before
   Termux can even see it, and — per `jetpacs-files.el`'s own comment —
   "Emacs's HOME on Android is a private per-app sandbox, so `/sdcard`
   is unreachable from the configured roots even though the rest of the
   device lives there." It's a detour through shared storage to reach
   an app that can't use shared storage as home turf.
2. `adb push` has no incremental mode; re-provisioning after a wipe
   means re-pushing every file every time, and there's no path to
   Termux's own home (where the Python fixture and `pylsp` need to
   live) without a second, different mechanism.

The fix: `com.termux` and `org.gnu.emacs` **share a Linux uid**. A
Termux shell — reached over `ssh`, not `adb push` — can read *and
write* both its own home **and** `org.gnu.emacs`'s app-private storage
directly, as the same POSIX owner. One transport (`rsync` over `ssh`,
port 8022, reached via `adb forward tcp:8022 tcp:8022`) covers every
destination below, `/sdcard` never enters the picture, and `rsync`
makes re-runs incremental instead of a full re-push.

`rsync`, not `scp`, for **every** file including the single ones:
OpenSSH 9+ `scp` speaks SFTP by default, which would add a dependency
on Termux's `sftp-server` being present and enabled for no benefit,
while `rsync` is already required for the tree sync.

## Device path constants

| Name | Value | Status |
|---|---|---|
| `TERMUX_HOME` | `/data/data/com.termux/files/home` | **fact** |
| `TERMUX_BIN` | `/data/data/com.termux/files/usr/bin` | **fact** |
| `EMACS_HOME` | `/data/data/org.gnu.emacs/files` *or* `/data/user/0/org.gnu.emacs/files` | **probed at run time**, never assumed — see below |
| `EMACS_DOTDIR` | `$EMACS_HOME/.emacs.d` | derived; the provisioner `mkdir -p`s it |
| Companion | `127.0.0.1:8765`, dialed *by the device* | **fact** |
| sshd | Termux, port 8022, forwarded via `adb forward tcp:8022 tcp:8022` | **fact** (mechanism); started by the typed bootstrap |

`EMACS_HOME` is probed rather than hardcoded because Emacs's Android
port sets `HOME` from `getFilesDir().getCanonicalPath()`
(`src/android.c`: `setenv ("HOME", android_files_dir, 1)`), and which
of the two paths that canonicalizes to is a property of the OS build,
not of this repo. `tools/onboard-provision-remote.sh` tries both and
reports which one it found.

`EMACS_DOTDIR` is load-bearing in a way that is easy to miss: Emacs
30.1's `startup--xdg-or-homedot` returns `~/.emacs.d` **the moment that
directory exists**, ahead of any XDG `~/.config/emacs`. Creating it is
what decides where the init is read from.

## Deploy table

| Repo path | Device path | Transport | Purpose |
|---|---|---|---|
| `emacs/` (whole tree, incl. `apps/`, `spike/`, READMEs) | `$TERMUX_HOME/jetpacs/emacs/` | `rsync -rlptz --delete` over `ssh -p 8022`, minus the excludes below | The elisp the device Emacs loads. Mirrored, not cherry-picked. |
| `device/py/` | `$TERMUX_HOME/jetpacs/py/` | `rsync -rlptz` (**no `--delete`**) | The eglot/pylsp fixture — and a live editing directory. |
| `device/emacs-init.el` | `$EMACS_DOTDIR/jetpacs-onboard-init.el` | staged to `$TERMUX_HOME/jetpacs/`, then `cp` by the on-device provisioner through the shared uid | The onboarding/eglot harness. |
| (generated) | one `(load ".../jetpacs-onboard-init.el" nil t)` line **appended** to `$EMACS_DOTDIR/init.el` | written by the on-device provisioner | Wires the harness without owning the file. |
| `tools/onboard-provision-remote.sh` | `$TERMUX_HOME/.onboard-provision.sh` | `rsync` | The device-side half; run over the same ssh session. |

`device/init.el` is **not** part of this bundle. It is the `/sdcard`
daily driver, deployed by `device/install.sh`, and it hardcodes the
`/sdcard/Documents/jetpacs` load-path. It is named here only because
the two flows collide in one file — see the next section.

### The init.el collision (the thing most likely to bite)

`docs/ONBOARDING-device.md`'s daily-driver setup tells you to put

```elisp
(load "/sdcard/Documents/jetpacs/init.el")
```

into `$EMACS_DOTDIR/init.el`. That is the *same file* this bundle needs
to wire its harness from. Installing `device/emacs-init.el` *as*
`init.el` — the obvious move — would silently uninstall the daily
driver, and a later `device/install.sh` user would have no idea why
their tablet stopped connecting.

So the provisioner never writes `init.el` wholesale:

- the harness lands beside it as `jetpacs-onboard-init.el`;
- `init.el` gains **one appended** `(load ...)` line (backed up first,
  once, if there was prior content);
- re-runs detect the line by name and leave the file alone entirely.

Appending — not prepending — is deliberate: anything already in
`init.el` runs first and gets the Companion session, and the harness's
stage 5 checks `jetpacs--client` before dialing, so it stands down
rather than racing `jetpacs-attach`'s single-client error. The harness
then contributes only what is additive: `exec-path`/`PATH`, the Termux
`load-path` entry, and the `jetpacs-files-roots` entry.

### Sync excludes, and why each one matters

`--exclude='*.elc'` — a stale `.elc` **silently shadows** the `.el` it
was built from; the repo's own `.gitignore` says exactly this. Syncing
one would ship a build of some older source and every symptom would
point at the wrong file. The provisioner additionally *deletes* any
`.elc` it finds already on the device.
`--exclude='.#*'` — Emacs lock files are dangling symlinks
(`user@host:pid`).
`--exclude='*~' --exclude='#*#'` — backups and autosaves.
`--exclude='.git' --exclude='__pycache__'` — noise.

### `--delete` on `emacs/`, but NOT on `py/`

`emacs/` is a mirror: a module deleted from the repo disappears from
the device on the next run, which is what keeps the flat load-path
honest. `py/` is **not** mirrored, because
`device/emacs-init.el` points `jetpacs-files-default-dir` at it — it is
a directory the tablet's Files app can create and edit files in, and a
mirror would delete the user's on-device work every time the script
ran. Repo files still win on a name collision, so `live.py` stays
authoritative.

### Why the whole tree, not a filtered copy

`emacs/spike/jetpacs-spike-rows.el` and the `README.md`/`RESULTS.md`
files are not on any `require` chain, so they're inert weight on the
device. They ride along anyway because mirroring the entire directory
with one `rsync` is simpler than maintaining a list of which files
matter, and it is forward-compatible for free: a future module dropped
anywhere under `emacs/` (a new `apps/<name>/`, a new top-level
`jetpacs-*.el`) reaches the device on the next run with zero script
changes, because the sync isn't reading any `require` list — it's
mirroring a directory.

### Load-path mechanics: the tree survives on its own

Preserving `emacs/apps/m3-catalog/` as a real subdirectory (instead of
`install.sh`'s flatten-into-one-directory convention) is what
`jetpacs-m3-catalog.el` is *already written for*. Its entry point
carries this:

```elisp
(eval-and-compile
  (let* ((here (or load-file-name buffer-file-name))
         (dir (and here (expand-file-name
                         "apps/m3-catalog" (file-name-directory here)))))
    (when (and dir (file-directory-p dir))
      (add-to-list 'load-path dir))))
```

It computes `apps/m3-catalog` relative to its own file's directory and
adds it to `load-path` only `when` that directory really exists next to
it. Under `install.sh`'s flatten it never exists (everything is already
flat, so the check is a no-op and `require` still finds every
`jetpacs-m3-*` file). Under this bundle's tree-preserving sync it
*does* exist, so the same unmodified code self-registers it.
`device/emacs-init.el` also walks `apps/*` generically, so a future app
that does *not* self-register still works.

Verified this session: no two `.el` files under `emacs/` share a
basename, so one flat load-path entry never masks a same-named module.
`tools/onboard-tablet.sh` re-checks this every run as a preflight,
because it is a property of *future* commits, not something this
manifest can freeze.

### The `~` trap

Three processes touch these paths, each with its own `$HOME` / `~`:

1. The **desktop** shell running `tools/onboard-tablet.sh` — `~` is the
   desktop user's home. Irrelevant to the device, easy to typo into a
   remote path by habit.
2. The **Termux ssh session** used as the transport — `~` *is*
   `$TERMUX_HOME`.
3. **`org.gnu.emacs`'s own Elisp process** — `~` expands via
   `(getenv "HOME")` *inside that process*, i.e. `$EMACS_HOME`, not
   `$TERMUX_HOME`, even though both are readable and writable by the
   same uid.

Consequence: any path written *inside* the harness — the `load-path`
entry, `jetpacs-files-roots`, the fixture location — must be the
literal absolute Termux path, never `~/jetpacs/...`. `~/jetpacs/...`
inside the harness silently resolves to a nonexistent directory under
`$EMACS_HOME`, and every `require` and `jetpacs-files` lookup fails
quietly. This is the easiest way to ship a bundle that looks
provisioned (the files really are on the device) but does not load.

### The fixture (`device/py/live.py`)

A class `Answer` with one **documented** method (`alpha`, docstring
`"The alpha needle documentation."`) and one undocumented one (`beta`),
then `a = Answer()`, then a bare `a.` as the **last two bytes of the
file — no trailing newline** (verified: 1199 bytes, ending `61 2e`).

Scope of that byte-exactness, stated honestly: it matters for a
**desktop-driven** `edit.open` that seeds `:cursor` as the fixture's own
length — the pattern `test/smoke-eglot-lsp.el` uses for its JS fixture
(`smoke-lsp--seed`, ending in a bare `answer.`). It does **not** matter
for the on-device Files flow, where the cursor comes from wherever the
user taps. So a trailing newline would not break the device demo; it
would break a future desktop-seeded probe written against this file.
The provisioner checks the two bytes either way and warns rather than
failing.

`ebp-sync-eglot-modes` already includes `python-mode` and
`python-ts-mode` by default, so no elisp config is needed for the mode
trigger — only `exec-path`/`PATH` (so `eglot-alternatives` can
`executable-find` `pylsp`) and `jetpacs-files-roots`.

### Idempotency

- `rsync --delete` on `emacs/` is a true mirror and a no-op when
  nothing changed.
- `py/` syncs without `--delete`, so device-side files survive.
- The harness is copied only when its sha256 differs.
- `init.el` is touched only when it does not already name the harness.
- `adb forward` is re-established every run (it does not survive a
  device reboot or an `adb` server restart).
- The typed bootstrap is skipped entirely once `ssh` answers.

## Runtime checks

- **`EMACS_HOME`'s literal value.** Probed by the provisioner across
  both candidates; read the value it reports before trusting anything
  downstream.
- **Write access into `$EMACS_DOTDIR` from Termux.** Shared uid grants
  POSIX ownership, but Android SELinux can additionally scope by
  per-package category on some OS builds. The provisioner does an
  explicit `touch`+`rm` probe and dies with a named message rather than
  discovering it during the install.
- **sshd running and reachable.** `adb forward` only forwards a port;
  it does not start Termux's sshd, and it does not survive a reboot.
- **`pylsp` under `$TERMUX_BIN`.** The provisioner warns loudly if
  `pylsp` resolves somewhere else, because the harness only adds
  `$TERMUX_BIN` to `exec-path`.
- **No new basename collision under `emacs/`.** Preflight, every run.
- **`live.py`'s last two bytes** after transfer.

## Manual steps

1. Open Termux once, so a process exists to type into. The script
   launches it and **verifies focus with `dumpsys`** before typing —
   it will not type a shell command into whatever else happens to be
   in front.
2. Accept Termux's own first-launch permission dialogs (notifications
   etc.). Not storage: this bundle never touches `/sdcard`.
3. Open the EBP Companion app so its `127.0.0.1:8765` listener is bound.
4. Launch (or force-stop and relaunch) `org.gnu.emacs` so it reads the
   newly wired init.
