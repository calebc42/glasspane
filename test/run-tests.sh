#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
glasspane_root=$(pwd)
repositories_root=${JETPACS_REPOSITORIES_ROOT:-"$(CDPATH= cd -- "$glasspane_root/.." && pwd)"}
jetpacs_dir=${JETPACS_DIR:-${JETPACS_ROOT:-}}
if test -z "$jetpacs_dir"; then
  for candidate in "$repositories_root/jetpacs-poc" \
                  "$repositories_root/jetpacs" \
                  "$repositories_root/jetpacs/jetpacs-poc"; do
    if test -r "$candidate/emacs/jetpacs-widgets.el"; then
      jetpacs_dir=$candidate
      break
    fi
  done
fi
ebp_el_dir=${EBP_EL_DIR:-"$repositories_root/ebp.el"}
ebp_org_dir=${EBP_ORG_DIR:-"$repositories_root/ebp-org"}
material_dir=${GLASSPANE_MATERIAL3_DIR:-"$jetpacs_dir/emacs/apps/jetpacs-material3"}

for suite in glasspane-reader-layout-test glasspane-navigation-test glasspane-timestamp-test glasspane-fab-test glasspane-pane-test glasspane-para-test glasspane-test; do
  emacs -Q --batch \
    -L "$ebp_el_dir/lisp" -L "$ebp_org_dir/lisp" \
    -L "$jetpacs_dir/emacs" \
    -L "$material_dir" \
    -L . -L test \
    --eval '(setq load-prefer-newer t)' \
    -l "test/$suite.el" -f ert-run-tests-batch-and-exit
done

# Checkdoc over every source file.  TODO: report-only for now — 141
# findings at the time this landed (mostly arguments not named in the
# docstring); make it fail the run once they are fixed.
emacs -Q --batch \
  -L "$ebp_el_dir/lisp" -L "$ebp_org_dir/lisp" \
  -L "$jetpacs_dir/emacs" -L "$material_dir" -L . \
  --eval '(setq load-prefer-newer t)' \
  --eval "(progn (require 'checkdoc) (dolist (file (directory-files \"$glasspane_root\" t \"\\\\.el\\\\'\")) (checkdoc-file file)))"

# Warning-as-error compile of every source file, into a directory this run
# owns: a developer's .elc beside the source is neither read nor replaced.
compile_output=$(mktemp -d /tmp/glasspane-compile.XXXXXX)
trap 'rm -rf "$compile_output"' EXIT HUP INT TERM
GLASSPANE_COMPILE_OUTPUT="$compile_output" \
emacs -Q --batch \
  -L "$ebp_el_dir/lisp" -L "$ebp_org_dir/lisp" \
  -L "$jetpacs_dir/emacs" -L "$material_dir" -L . \
  --eval '(setq load-prefer-newer t)' \
  --eval "(setq byte-compile-error-on-warn t byte-compile-dest-file-function (lambda (file) (expand-file-name (concat (file-name-nondirectory file) \"c\") (getenv \"GLASSPANE_COMPILE_OUTPUT\"))))" \
  -f batch-byte-compile "$glasspane_root"/*.el

sources=$(find "$glasspane_root" -maxdepth 1 -name '*.el' | wc -l)
compiled=$(find "$compile_output" -maxdepth 1 -name '*.elc' | wc -l)
if test "$compiled" -ne "$sources"; then
  echo "glasspane compile: $compiled of $sources files compiled" >&2
  exit 1
fi
