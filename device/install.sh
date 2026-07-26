#!/usr/bin/env bash
# Push the Jetpacs elisp + the device init to /sdcard/Documents/jetpacs/.
# Re-run after every elisp change; then restart the device Emacs (or
# M-x jetpacs-stop, re-load, M-x jetpacs-start).
set -euo pipefail
cd "$(dirname "$0")/.."
adb shell mkdir -p /sdcard/Documents/jetpacs
for f in emacs/*.el device/init.el; do
  adb push "$f" /sdcard/Documents/jetpacs/ >/dev/null
done
echo "pushed $(ls emacs/*.el | wc -l) modules + init.el to /sdcard/Documents/jetpacs/"
