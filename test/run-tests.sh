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
  -l glasspane-gallery-test \
  -l glasspane-jetpacs-test \
  -l glasspane-journal-test \
  -l glasspane-notes-test \
  -l glasspane-org-test \
  -l glasspane-pack-test \
  -l glasspane-source-test \
  -l glasspane-sparse-test \
  -l glasspane-srs-test \
  -l glasspane-ui-test \
  -l glasspane-views-test \
  -f ert-run-tests-batch-and-exit </dev/null