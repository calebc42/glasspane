# Onboarding: Jetpacs on the device

> **Field note (2026-08-13, first live run):** the tree transport is now
> `tar` over the ssh exec channel, not rsync — Termux's rsync 3.5.0
> receiver hit an unexplained EACCES on chdir into a directory the same
> ssh login enters fine (no AVC, correct owner/modes). And pubkey auth
> is not assumed: Termux's openssh 10.5p1 accepted the ed25519 in the
> authorized_keys exchange yet denied the signed auth, so the kit keeps
> a generated password in `tools/onboard-scratch/` and serves it via
> `SSH_ASKPASS` whenever the key path fails.


The elisp lives at `/sdcard/Documents/jetpacs/` (refreshed over adb);
the device Emacs's app-private init needs exactly ONE line.

**Re-provisioning a wiped tablet, or bringing up Termux + `pylsp` for
the eglot/language-server work:** use `tools/onboard-tablet.sh` instead
of the steps below. It is the single desktop command for that path —
Termux + sshd, the elisp tree, the `device/py/` fixtures, and
`device/emacs-init.el` all land over one `ssh`/`rsync` transport
(`com.termux` and `org.gnu.emacs` share a uid on this device, so a
Termux shell can write straight into `org.gnu.emacs`'s app-private
storage — no `/sdcard`, no storage permission dialog). See
`device/MANIFEST.md` for exactly what lands where and why.

The two flows **share one file**: step 3 below writes a `load` line
into `~/.emacs.d/init.el`, and that is the same `init.el` the onboard
script has to wire its harness from. So the script never overwrites it.
It installs the harness beside it as `~/.emacs.d/jetpacs-onboard-init.el`
and *appends* one `(load ...)` line, leaving anything already there to
run first; the harness then declines to dial the Companion when a
client is already attached. Net effect: run either flow, or both, in
either order — the daily driver keeps the session and the harness
contributes only `exec-path`/`PATH`, the Termux `load-path`, and the
`jetpacs-files-roots` entry.

## One-time setup

1. From the workstation, with the tablet on adb:

   ```
   ./device/install.sh
   ```

   This pushes every `emacs/*.el` module plus `device/init.el` to
   `/sdcard/Documents/jetpacs/`.

2. On the DEVICE, make sure Emacs has storage permission
   (Android settings → Apps → Emacs → Permissions → Files, "allow all").

3. On the DEVICE, add one line to `~/.emacs.d/init.el` (create it if
   absent — `C-x C-f ~/.emacs.d/init.el`):

   ```elisp
   (load "/sdcard/Documents/jetpacs/init.el")
   ```

4. Restart Emacs (or `M-x load-file` that init).  Emacs auto-connects
   to the Companion on localhost and the **hub** appears: Scratch,
   Messages, and Shell rows (tap to drill in — Shell gets the comint
   input field), a Theme toggle in the top bar.

## Daily commands (on the device)

- `M-x jetpacs-hub` — bring the hub back to the screen from anywhere.
- `M-x jetpacs-clip-show` — the kill ring, one tap per entry to the
  device clipboard.  (Auto-refresh is off: every kill would otherwise
  claim the screen.)
- `M-x jetpacs-start` / `M-x jetpacs-stop` — reconnect / disconnect.
- `M-x jetpacs-theme-send` — one-shot palette push.

## Updating

Re-run `./device/install.sh` after any elisp change, then on the
device: `M-x jetpacs-stop`, `M-x load-file /sdcard/Documents/jetpacs/init.el`,
`M-x jetpacs-start`.  (Or just restart Emacs.)

## Two sharp edges

- **One session.** The Companion binds ONE Emacs.  If the device Emacs
  is running with this init, it grabs the session the moment the
  Companion starts — a workstation Emacs dialing through
  `adb forward` will be refused ("Server exited with status 256" is
  what that looks like from the WSL side).  For workstation smokes,
  quit the device Emacs first.
- **Ghost sessions over adb.** A killed workstation Emacs can leave an
  ESTABLISHED socket held by adbd; the Companion stays bound to the
  ghost and refuses newcomers.  `adb forward --remove-all`, force-stop
  the Companion, and start fresh.
