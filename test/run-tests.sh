#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
jetpacs_dir=${JETPACS_DIR:-${JETPACS_ROOT:-}}
if test -z "$jetpacs_dir"; then
  for candidate in "$(pwd)/../jetpacs-poc" \
                  "$(pwd)/../jetpacs" \
                  "$(pwd)/../jetpacs/jetpacs-poc"; do
    if test -r "$candidate/emacs/jetpacs-widgets.el"; then
      jetpacs_dir=$candidate
      break
    fi
  done
fi
ebp_el_dir=${EBP_EL_DIR:-"$(pwd)/../ebp.el"}
ebp_org_dir=${EBP_ORG_DIR:-"$(pwd)/../ebp-org"}
material_dir=${GLASSPANE_MATERIAL3_DIR:-"$jetpacs_dir/emacs/apps/jetpacs-material3"}

for suite in glasspane-reader-layout-test glasspane-navigation-test glasspane-para-test glasspane-test; do
  emacs -Q --batch \
    -L "$ebp_el_dir/lisp" -L "$ebp_org_dir/lisp" \
    -L "$jetpacs_dir/emacs" \
    -L "$material_dir" \
    -L . -L test \
    --eval '(setq load-prefer-newer t)' \
    -l "test/$suite.el" -f ert-run-tests-batch-and-exit
done
