# Onboarding: Jetpacs on the device

The elisp lives at `/sdcard/Documents/jetpacs/` (refreshed over adb);
the device Emacs's app-private init needs exactly ONE line.

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
