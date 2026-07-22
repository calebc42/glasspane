#!/bin/sh
# W1 conformance suite: emacs batch ERT over the ebp golden corpus.
set -e
cd "$(dirname "$0")/.."
emacs -Q --batch -L emacs -l test/ebp-wire-test.el \
  -f ert-run-tests-batch-and-exit
