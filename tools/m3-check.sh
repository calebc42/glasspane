#!/usr/bin/env bash
# Gate ONE catalog component module: byte-compile (warnings are errors)
# and then build/validate every screen it contributes.
#
#   tools/m3-check.sh buttons [more-slugs...]
#
# Compiled output goes to a temp directory, never beside the sources —
# a stale .elc would shadow a sibling module for every other check
# running at the same time.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -eq 0 ]; then
  echo "usage: tools/m3-check.sh <component-slug> [...]" >&2
  exit 2
fi

dest=$(mktemp -d)
trap 'rm -rf "$dest"' EXIT

for slug in "$@"; do
  file="emacs/apps/m3-catalog/jetpacs-m3-${slug}.el"
  if [ ! -f "$file" ]; then
    echo "m3-check: no module $file" >&2
    exit 2
  fi
  emacs -Q --batch -L emacs -L emacs/apps/m3-catalog \
    --eval "(progn
              (setq byte-compile-error-on-warn t)
              (setq byte-compile-dest-file-function
                    (lambda (f)
                      (expand-file-name (concat (file-name-nondirectory f) \"c\")
                                        \"$dest\"))))" \
    -f batch-byte-compile "$file"
done

emacs -Q --batch -L emacs -L emacs/apps/m3-catalog \
  -l tools/m3-check.el -f jetpacs-m3-check-batch "$@"
