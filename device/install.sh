#!/usr/bin/env bash
# Compatibility entry point for the former /sdcard/Documents/jetpacs deploy.
# There is no second "daily driver" anymore: use the same onboarding path and
# its recommended /sdcard Vault. HOME, init.el, and the managed tree remain in
# the private Emacs/Termux home and cannot drift apart.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
exec "$SCRIPT_DIR/../tools/onboard-tablet.sh" \
  --vault shared --emacs-home emacs "$@"
