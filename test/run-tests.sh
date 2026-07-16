#!/usr/bin/env bash
# Run the Glasspane ERT suites against the vendored jetpacs core.
set -euo pipefail
cd "$(dirname "$0")/.."

EMACS="${EMACS:-emacs}"

"$EMACS" --batch \
  -L jetpacs/emacs/core \
  -L emacs/apps/glasspane \
  -L test \
  -l glasspane-test-helpers \
  -l glasspane-automations-test \
  -l glasspane-config-test \
  -l glasspane-core-test \
  -l glasspane-demo-test \
  -l glasspane-ef-test \
  -l glasspane-gallery-test \
  -l glasspane-jetpacs-test \
  -l glasspane-journal-test \
  -l glasspane-notes-test \
  -l glasspane-org-test \
  -l glasspane-pack-test \
  -l glasspane-packages-test \
  -l glasspane-source-test \
  -l glasspane-sparse-test \
  -l glasspane-srs-test \
  -l glasspane-ui-test \
  -l glasspane-views-test \
  -l glasspane-vulpea-test \
  -f ert-run-tests-batch-and-exit </dev/null

# The foundation byte-compiles an adopted bundle BEFORE loading it, when
# none of the bundle's own features exist on the load-path — a surviving
# bundle-internal hard require is a compile error and a broken .elc on
# device.  Compile the shipped bundle against the core bundle alone
# (exactly the device situation) to pin that.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp jetpacs/jetpacs-core.el glasspane.el "$tmp"/
"$EMACS" -Q --batch -L "$tmp" --eval "(progn (require 'bytecomp)
  (let ((byte-compile-warnings nil))
    (unless (byte-compile-file \"$tmp/glasspane.el\")
      (kill-emacs 1))))"
echo "bundle byte-compiles standalone: OK"