#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
jetpacs_dir=${JETPACS_DIR:-"$(pwd)/../jetpacs"}
ebp_el_dir=${EBP_EL_DIR:-"$(pwd)/../ebp-poc/ebp.el"}
ebp_org_dir=${EBP_ORG_DIR:-"$(pwd)/../ebp-poc/ebp-org"}
material_dir=${GLASSPANE_MATERIAL3_DIR:-"$(pwd)/../glasspane-material3"}

for suite in glasspane-reader-layout-test glasspane-navigation-test glasspane-para-test glasspane-test; do
  emacs -Q --batch \
    -L "$ebp_el_dir/lisp" -L "$ebp_org_dir/lisp" \
    -L "$jetpacs_dir/emacs" \
    -L "$material_dir/lisp/glasspane-material3" \
    -L . -L test \
    --eval '(setq load-prefer-newer t)' \
    -l "test/$suite.el" -f ert-run-tests-batch-and-exit
done
