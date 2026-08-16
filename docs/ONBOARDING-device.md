# Onboarding Jetpacs on Android

POC 3 begins with one decision: **Recommended** or **Advanced**.

- **Recommended** is the fixed device-local preset: Local Emacs's private
  `HOME` owns `.emacs.d/jetpacs`, and `/sdcard` is the user-content Vault.
- **Advanced** chooses the Emacs host first—Local Emacs, Remote Emacs, or
  Termux—then offers only the Vault locations appropriate to that host and
  shows the exact startup snippets involved.

Run the interactive flow with:

```sh
tools/onboard-tablet.sh
```

For automation, pass both dimensions explicitly:

```sh
tools/onboard-tablet.sh --vault shared --emacs-home emacs
```

## Recommended

Recommended installs this pairing without asking two separate path questions:

| Concern | Selection |
|---|---|
| Unix `HOME` and `.emacs.d/jetpacs` | Local Emacs private home |
| Vault | `/sdcard` |

This is the default for local Org Mode. User content survives uninstalling
Emacs, although any app granted Android **All files** access can read it. Grant
Android Emacs **All files** access so it can use the Vault.

The Recommended screen has one **Prepare files and copy setup** button. Pressing
it saves the APK's bundled payload temporarily under
`/sdcard/Documents/jetpacs-installer/` and copies Jetpacs's exact marked package
entry. The screen then tells the user to:

1. open `~/.emacs.d/init.el` in Android Emacs, creating it if necessary;
2. paste the block at the bottom without replacing existing configuration; and
3. save the file and return to the Companion.

The Companion does not request access to or edit Emacs's private files. The
existing init remains first and therefore runs before Jetpacs. On the next full
Emacs start, the one-time bootstrap creates or repairs
`~/.emacs.d/jetpacs/`, records `/sdcard` as the Vault, removes the temporary
handoff, and finishes with `(require 'jetpacs)`. The Recommended flow downloads
nothing and has no Termux, shell, or `early-init.el` step.

## Advanced: choose the Emacs HOME first

| Choice | Unix `HOME` | Managed root | Startup material shown |
|---|---|---|---|
| Local Emacs | Android Emacs's probed private home | `EMACS_HOME/.emacs.d/jetpacs` | marked block for `EMACS_HOME/.emacs.d/init.el` |
| Remote Emacs | remote user's existing home | remote `~/.emacs.d/jetpacs` state | one-time `package-vc-install`, pairing ID/token, `(require 'jetpacs)`, and adb port forward |
| Termux | `/data/data/com.termux/files/home` | `TERMUX_HOME/.emacs.d/jetpacs` | Android Emacs `early-init.el` redirect plus Termux `init.el` block |

Both Android-local HOME choices are private app storage. `.emacs.d` is never
placed on `/sdcard`.

## Advanced: choose an eligible Vault

| Choice | Vault path | Persistence and exposure |
|---|---|---|
| `/sdcard` | `/sdcard` | Survives uninstalling Emacs or Termux. Any app granted Android **All files** access can read it. |
| Emacs home | Android Emacs's probed private home | Other ordinary apps cannot read it. It is deleted with Emacs app data. |
| Termux home | `/data/data/com.termux/files/home` | Termux tools can work on the content directly. It is deleted with Termux app data. |
| Remote Emacs home | remote `~/` | Remote content stays on the remote host. Android-local paths are not presented as ordinary remote filesystems. |

Local Emacs offers `/sdcard` and Local Emacs home. Termux offers all three
Android-local Vaults. Remote Emacs uses its remote home. In particular, Termux
home is not offered as a Vault for Local or Remote Emacs.

The selected Vault supplies defaults for the Files landing directory and
`org-directory` (`VAULT/org/`). Values already set by the user's init or Custom
win, and Jetpacs never changes the user's `default-directory`. The Vault never
becomes a second Jetpacs configuration tree.

## Package boundary: install once, require from init

Installation and loading are separate Emacs operations. `(require 'jetpacs)`
loads the named feature only after Jetpacs is available on `load-path`; it does
not contact MELPA or any other archive.

Recommended and Advanced Android setup install the APK's bundled copy so a new
user does not need a package archive, Git, or Termux. Existing desktop/remote
Emacs users can install directly from the repository once:

```elisp
(package-vc-install
 '(jetpacs :url "https://github.com/calebc42/jetpacs"
            :lisp-dir "emacs"))
```

Their existing `init.el` then needs only its pairing values followed by:

```elisp
(require 'jetpacs)
```

Once Jetpacs is published in an Emacs package archive, `M-x package-install`
or a user's existing `use-package :ensure` convention can replace the one-time
installation command. The init-side `(require 'jetpacs)` contract does not
change. Emacs Custom remains the persistence backend for settings changed in
the Jetpacs Settings screen.

## Startup chains

Recommended uses an explicit clipboard handoff because the Companion cannot
safely edit another app's private Emacs configuration:

```text
Companion bundled handoff
  -> Companion stages /sdcard/Documents/jetpacs-installer
  -> Companion copies the marked Jetpacs package entry
  -> user pastes it at the bottom of ~/.emacs.d/init.el and saves
  -> marked Jetpacs package entry
  -> consumes /sdcard/Documents/jetpacs-installer once, when present
  -> creates or repairs ~/.emacs.d/jetpacs
  -> removes the temporary handoff
  -> adds bundled package code to load-path
  -> (require 'jetpacs)
```

Advanced local installation uses the lower-level startup chain below.

Launch Android Emacs once so its original private home exists, then force-stop
it before installing. The installer probes that bootstrap home as either
`/data/data/org.gnu.emacs/files` or `/data/user/0/org.gnu.emacs/files`.

```text
ORIGINAL_EMACS_HOME/.emacs.d/early-init.el
  -> keeps Local Emacs HOME or selects Termux HOME
  -> Emacs naturally loads SELECTED_HOME/.emacs.d/init.el
  -> one marked block adds bundled code to load-path
  -> (require 'jetpacs)
  -> install.conf independently supplies the Vault
```

`early-init.el` does not load `init.el` itself. The Advanced setup also ships
the exact Termux executable-path forms exposed by the Companion's Copy button:

```elisp
(setenv "PATH" (format "%s:%s" "/data/data/com.termux/files/usr/bin"
		       (getenv "PATH")))
(push "/data/data/com.termux/files/usr/bin" exec-path)
```

The selected private tree is:

```text
SELECTED_HOME/.emacs.d/
├── init.el                         user-owned; one marked Jetpacs block
└── jetpacs/                        the removable Jetpacs boundary
    ├── init.el                     compatibility loader for older seams
    ├── install.conf                separate Vault and HOME selections
    ├── emacs/
    │   ├── jetpacs.el              public `(require 'jetpacs)` entry
    │   ├── jetpacs-init.el         composition and startup
    │   └── apps/                   bundled in-tree app modules
    ├── org/                        distribution Org seed/manual assets
    ├── examples/python/            optional development fixtures
    ├── apps/                       user-installed apps and app configuration
    ├── apps.el                     installed-app registry
    ├── var/                        receipts and durable protocol state
    ├── user.el                     optional overrides; never overwritten
    └── migration/                  recovery copies from retired layouts
```

The Companion also has receiver-local preferences, protocol outbox data, and
renderer caches under its own Android app data. Those are not an Emacs init or
Elisp tree.

## Reconnecting Android Emacs

If an authenticated local Emacs session disconnects, the Companion posts an
**Emacs disconnected** notification. Tapping it launches `org.gnu.emacs`
directly, as POC 1 did, without routing through the Companion or its onboarding
flow. The notification is cleared when the next Emacs session authenticates.
Failed unauthenticated connection attempts and teardown of a session already
superseded by a newer one do not post it.

## Existing configurations and changing HOME

Recommended never edits a user's init. The user deliberately pastes the marked
block at the bottom, leaving existing configuration above it. On repair, the
user should replace the existing marked Jetpacs block rather than adding a
second copy. The Advanced installer applies its replace-only-its-own-block rule
to `init.el` and `early-init.el` and creates a one-time preinstall backup.
Personal overrides belong in
`~/.emacs.d/jetpacs/user.el`, which loads last and survives updates.

If the Unix-HOME choice changes later, the installer copies `apps/`, `apps.el`,
`var/`, and `user.el` to the newly selected private home before changing
startup. It archives the previous managed root under `migration/`, removes only
the old marked init seam, and then retires the inactive managed root. User init
forms are preserved. The Vault does not move.

The retired POC 3 `jetpacs-onboard-init.el` harness and its durable state are
handled by the same copy-before-startup migration.

## Updating, auditing, and removing

For a Recommended repair or update, reopen setup, press **Prepare files and copy
setup**, replace the existing marked Jetpacs block in `init.el` with the fresh
copy, save, and restart Emacs. Emacs then consumes the fresh handoff and
refreshes only distribution-owned paths. `apps/`, `apps.el`, `var/`, `user.el`,
the rest of `init.el`, and the Vault survive.

The commands below are the Advanced/desktop maintenance interface.

Rerun installation with the same pair to update distribution files:

```sh
tools/onboard-tablet.sh --vault shared --emacs-home emacs
```

Audit without changing anything:

```sh
tools/onboard-tablet.sh --audit --vault shared --emacs-home emacs
```

Remove Jetpacs while preserving the Vault and early-init HOME/PATH selection:

```sh
tools/onboard-tablet.sh --remove --vault shared --emacs-home emacs
```

This removes the marked normal-init seam and the validated
`SELECTED_HOME/.emacs.d/jetpacs` tree. To separately remove the managed
early-init block:

```sh
tools/onboard-tablet.sh --reset-home --vault shared --emacs-home emacs
```

Neither operation deletes the Vault.

## Legacy directories

The installer reports but does not automatically delete these obsolete POC 3
locations because they may contain user edits:

- `/sdcard/Documents/jetpacs`
- `/data/data/com.termux/files/home/jetpacs`

They are not on the new startup path. Inspect them before deleting them.

After installation, force-stop and relaunch Android Emacs, then open the EBP
Companion. Only one Emacs should own the Companion session at a time; stop the
local Android Emacs before connecting Remote Emacs.
