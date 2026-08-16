# Device installation contract

This is the deploy contract implemented by `tools/onboard-tablet.sh` and
`tools/onboard-provision-remote.sh`.

## Invariants

1. Vault and Unix `HOME` are independent selections.
2. The Vault is `/sdcard`, Android Emacs's private home, or Termux's private
   home. It owns user content, not Jetpacs internals.
3. Local Unix `HOME` is Android Emacs's private home or Termux's private home.
   `.emacs.d` is never on `/sdcard`.
4. Android Emacs's original private `.emacs.d/early-init.el` contains one
   marked HOME/PATH-selection block, plus unrelated user content.
5. A bundled installation's selected `.emacs.d/init.el` contains one marked
   load-path entry followed by `(require 'jetpacs)`.
6. Every mutable Emacs-side Jetpacs state file is below the selected
   `.emacs.d/jetpacs/` boundary. Package-manager code may instead live in
   `package-user-dir`; it uses the same state boundary.
7. Updating distribution code never deletes `apps/`, `apps.el`, `var/`, or
   `user.el`.
8. Changing Unix `HOME` migrates durable state before startup changes, archives
   the old managed root, removes its marked init seam, and retires that root.
9. Retired harness state is copied under `jetpacs/migration/`. Old standalone
   Termux `~/jetpacs` and `/sdcard/Documents/jetpacs` trees are reported but
   never automatically deleted because they may contain user edits.
10. Recommended onboarding never edits Android Emacs's private files. It stages
    the bundled handoff and copies one exact managed block for the user to paste
    at the bottom of `.emacs.d/init.el` without replacing existing content.

The Companion's event queue, preferences, and renderer caches remain in its
own Android-private app data. They are not a competing Emacs configuration.

## Independent path dimensions

Unix `HOME` determines the private managed root:

| `--emacs-home` | `SELECTED_HOME` | `JETPACS_ROOT` |
|---|---|---|
| `emacs` | probed `/data/data/org.gnu.emacs/files` or `/data/user/0/org.gnu.emacs/files` | `$SELECTED_HOME/.emacs.d/jetpacs` |
| `termux` | `/data/data/com.termux/files/home` | `$SELECTED_HOME/.emacs.d/jetpacs` |
| `remote` | no Android selection | no Android mutation |

Vault mode independently determines user-content paths:

| `--vault` | `VAULT` |
|---|---|
| `shared` | `/sdcard` |
| `emacs` | the probed Android Emacs private home |
| `termux` | `/data/data/com.termux/files/home` |

The device-side installer keeps these dimensions separate and can migrate every
local pairing. The Companion presents a narrower onboarding policy: Local
Emacs offers `/sdcard` or Emacs home; Termux offers all three; Remote Emacs uses
its remote home. `install.conf` records `home_mode`, `home`, `vault_mode`, and
`vault` separately.

The original Android Emacs home cannot be replaced on disk: Emacs begins there
before user Lisp runs. Its marked early-init block either keeps Local Emacs
HOME or sets `HOME`, `default-directory`, and `user-emacs-directory` to Termux.
Normal startup then finds the selected init itself.

## Deploy table

| Repo path | Installed path below `JETPACS_ROOT` | Update policy |
|---|---|---|
| `device/init.el` | `init.el` | replace compatibility loader |
| `emacs/` | `emacs/` | replace distribution subtree; exclude byte-code and editor debris |
| `org/` | `org/` | replace distribution seed subtree; live Vault content is untouched |
| `device/py/` | `examples/python/` | replace managed examples |
| generated | `install.conf` | replace atomically |
| runtime | `var/` | preserve |
| app store/runtime | `apps/`, `apps.el` | preserve |
| user | `user.el` | preserve and never create |

Startup seams:

| Repo path | Destination | Policy |
|---|---|---|
| `device/early-init-local.el` or `device/early-init-termux.el` | marked block in original Android Emacs `.emacs.d/early-init.el` | replace only the managed block; back up original once |
| `device/init-seam.el` | marked block in selected `.emacs.d/init.el` | replace only the managed block; back up original once |

## Transport

The desktop script reaches Termux's SSH daemon through
`adb forward tcp:8022 tcp:8022`. A fresh transport-only payload is placed below
Termux `~/.cache/jetpacs-onboard/`, installed, and removed. It is never a
runtime load path.

Trees use `tar` over the SSH exec channel. Termux and this Android Emacs build
share a Linux identity, which allows the installer to modify Android Emacs's
private startup files. The installer probes that path rather than assuming its
spelling.

The Companion has no ambient access to either private home, so its generated
handoff is temporarily staged under
`/sdcard/Documents/jetpacs-installer/`. In Recommended, the Companion copies the
marked package entry and the user pastes it at the bottom of Android Emacs's
`~/.emacs.d/init.el`. That entry invokes
`device/install-recommended.el`, which refreshes only distribution-owned paths
below Local Emacs's `.emacs.d/jetpacs`, preserves durable paths, records the
`/sdcard` Vault, and removes the handoff. Advanced's displayed shell command
runs the lower-level installer and removes the same cache after a successful
install.

For an existing desktop/remote Emacs, package-vc can place code in
`package-user-dir` directly from the repository's `emacs/` Lisp directory.
Package activation supplies its load path; the user's init still activates the
application with `(require 'jetpacs)`. This package route does not change the
mutable-state boundary above.

## Mutation and removal boundaries

The device-side installer rejects relative, empty, and `/` homes and validates
deletion targets as the exact selected `$HOME/.emacs.d/jetpacs` path. Managed
block parsing fails closed on unmatched markers.

`remove` deletes only the selected init seam and validated managed root.
`reset-home` separately removes only the marked early-init HOME/PATH block.
Neither action deletes the Vault.
