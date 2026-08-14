#!/usr/bin/env bash
# Push the Jetpacs elisp + the device init to /sdcard/Documents/jetpacs/.
# Re-run after every elisp change; then restart the device Emacs (or
# M-x jetpacs-stop, re-load, M-x jetpacs-start).
set -euo pipefail
cd "$(dirname "$0")/.."
adb shell mkdir -p /sdcard/Documents/jetpacs
# emacs/apps/<app>/*.el is FLATTENED into the same directory: the device
# load-path is one directory (device/init.el), and every module's file
# name is already globally unique across the whole tree -- `jetpacs-' for
# the application layer, `ebp-' for the wire-and-Emacs layer -- so the
# subdirectory is a repo-side grouping only.
for f in emacs/*.el emacs/apps/*/*.el device/init.el; do
  adb push "$f" /sdcard/Documents/jetpacs/ >/dev/null
done
adb push org /sdcard/Documents/jetpacs/ >/dev/null
echo "pushed $(ls emacs/*.el emacs/apps/*/*.el | wc -l) modules + init.el \
and Org Mode seed assets to /sdcard/Documents/jetpacs/"
