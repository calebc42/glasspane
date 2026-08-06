#!/bin/sh
# elisp suites: delineation guard, then the ERT conformance suite.
set -e
cd "$(dirname "$0")/.."

# Delineation guard (REWRITE-PLAN "The ebp.el boundary"): ebp.el loads
# alone and defines nothing jetpacs-flavored.
emacs -Q --batch -L emacs --eval '
(progn
  (require (quote ebp))
  (let (offenders)
    (mapatoms
     (lambda (sym)
       (when (and (string-prefix-p "jetpacs" (symbol-name sym))
                  (or (fboundp sym) (boundp sym)))
         (push sym offenders))))
    (when offenders
      (message "delineation guard: jetpacs symbols after loading ebp.el: %S"
               offenders)
      (kill-emacs 1))
    (message "delineation guard: ebp.el loads alone, no jetpacs symbols")))'

# Byte-compile guard: free-variable and undefined-function warnings are
# treated as errors (catches unescaped-quote docstrings and typos before
# they reach a device).
emacs -Q --batch -L emacs \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile emacs/ebp.el
rm -f emacs/ebp.elc

# Same guard for EVERY application-layer module. A glob, not a list: the
# previous hand-kept 16-name list silently omitted jetpacs-modus.el, and a
# module added later would have been unguarded by default — the exact
# docstring-quote bug class this guard exists for would then reach a device.
# ebp.el compiles twice (here and above); two seconds buys never maintaining
# the list again.
# The glob covers emacs/apps/*/ too: a Tier-1 app that modularizes into a
# subdirectory (the M3 catalog is 42 files) must not escape the guard by
# living one level down.
for f in emacs/*.el emacs/apps/*/*.el; do
  emacs -Q --batch -L emacs -L emacs/apps/m3-catalog \
    --eval '(setq byte-compile-error-on-warn t)' \
    -f batch-byte-compile "$f"
  rm -f "${f%.el}.elc"
done

# Storage-independent SPEC 14.4 receipt/work contract and its built-in
# Emacs 30.1 SQLite backend.  No Jetpacs or ebp.el dependency.
emacs -Q --batch -L emacs -l test/ebp-store-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L emacs -l test/ebp-wire-test.el \
  -f ert-run-tests-batch-and-exit

# Section 19 buffer bridge on built-in track-changes.el (PLAN-poc1-parity
# P1); Jetpacs-agnostic like ebp.el itself.
emacs -Q --batch -L emacs -l test/ebp-sync-test.el \
  -f ert-run-tests-batch-and-exit

# Application-layer builder suite (jetpacs-widgets; requires ebp, so it is
# absent from the delineation guard above).
emacs -Q --batch -L emacs -l test/jetpacs-widgets-test.el \
  -f ert-run-tests-batch-and-exit

# JC-0 floor exit gate (docs/SPEC-JC-0-floor.md section 7).
emacs -Q --batch -L emacs -l test/jetpacs-floor-test.el \
  -f ert-run-tests-batch-and-exit

# JC-1 Tier-0 renderer exit gate (golden + budgets + D2 actions).
emacs -Q --batch -L emacs -l test/jetpacs-buffer-test.el \
  -f ert-run-tests-batch-and-exit

# JC-2 results/tablist skins exit gate.
emacs -Q --batch -L emacs -l test/jetpacs-results-test.el \
  -f ert-run-tests-batch-and-exit

# JC-3a/3c sections + comint skins exit gate.
emacs -Q --batch -L emacs -l test/jetpacs-sections-test.el \
  -f ert-run-tests-batch-and-exit

# JC-3b hypertext skin exit gate (golden + image resolver + nav).
emacs -Q --batch -L emacs -l test/jetpacs-hypertext-test.el \
  -f ert-run-tests-batch-and-exit

# JC-4a prompt floor exit gate (advice gating, dialog specs, conclusions).
emacs -Q --batch -L emacs -l test/jetpacs-dialog-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L emacs -l test/jetpacs-transient-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L emacs -l test/jetpacs-package-browser-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L emacs -l test/jetpacs-settings-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L emacs -l test/jetpacs-project-sql-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L emacs -l test/jetpacs-apps-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L emacs -l test/jetpacs-app-store-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L emacs -l test/jetpacs-home-test.el \
  -f ert-run-tests-batch-and-exit

# JC-5 completion harvester exit gate (the :edit-complete-function seam).
emacs -Q --batch -L emacs -l test/jetpacs-complete-test.el \
  -f ert-run-tests-batch-and-exit

# JA-1 theme + modus exit gate (docs/PLAN-jetpacs-apps.md).
emacs -Q --batch -L emacs -l test/jetpacs-theme-test.el \
  -f ert-run-tests-batch-and-exit

# JA-1 reminders wrapper exit gate.
emacs -Q --batch -L emacs -l test/jetpacs-device-test.el \
  -f ert-run-tests-batch-and-exit

# JA-1 clip view exit gate (golden: test/goldens/clip-view.golden).
emacs -Q --batch -L emacs -l test/jetpacs-clip-test.el \
  -f ert-run-tests-batch-and-exit

# JA-2 teardown exit gate (selector mandatory: the loopback harness file
# defines its own suite too).
emacs -Q --batch -L emacs -l test/ebp-wire-test.el -l test/jetpacs-teardown-test.el \
  --eval '(ert-run-tests-batch-and-exit "^jetpacs-teardown-")'

# JA-2 buffer-view host exit gate.
emacs -Q --batch -L emacs -l test/jetpacs-navigate-test.el \
  -f ert-run-tests-batch-and-exit

# JA-2 chrome kit exit gate.
emacs -Q --batch -L emacs -l test/jetpacs-chrome-test.el \
  -f ert-run-tests-batch-and-exit

# JA-4 exit gate: the org engine — refs/tokens (D-4), resolve guards,
# the cache key, mutations, and (from O2/O3) the query grammar and
# capture primitives.
emacs -Q --batch -L emacs -l test/jetpacs-org-test.el \
  -f ert-run-tests-batch-and-exit

# Vulpea arm (Tier-1 staging — jetpacs-org-vulpea.el, never required by
# base): synthetic-struct accessor semantics + index-evaluable routing.
emacs -Q --batch -L emacs -l test/jetpacs-org-vulpea-test.el \
  -f ert-run-tests-batch-and-exit

# JA-5b exit gate: the org render skin — the golden, native-upgrade
# budget charging (A2 cells, frame bytes), data:-URI images through the
# root allowlist, the span-action arms, the org_parser trap fixture,
# and the checkbox/widen verbs' gate order.
emacs -Q --batch -L emacs -l test/jetpacs-org-render-test.el \
  -f ert-run-tests-batch-and-exit

# JA-5d exit gate: the org dialogs — profile-pinned specs, drop-only
# remote descriptors, fresh ids, 23.2 re-validation, the engine-backed
# sheet mutations, token+confirm Archive, and the can-bridge gate.
emacs -Q --batch -L emacs -l test/jetpacs-org-dialogs-test.el \
  -f ert-run-tests-batch-and-exit

# JA-5g exit gate: the habits screen — the windowed graph with rotten
# habits skipped, the one-canvas strip's A2 spend, the durable Done
# with the prompt hazard loud, token honesty, and the grep pin keeping
# the walk off the raw agenda forms.
emacs -Q --batch -L emacs -l test/jetpacs-org-habits-test.el \
  -f ert-run-tests-batch-and-exit

# JA-5h: the Tier-1 outline STAGING view (never required by base) —
# own-records cards, the cap/seam/empty body, the no-base-require pin.
emacs -Q --batch -L emacs -l test/jetpacs-org-outline-test.el \
  -f ert-run-tests-batch-and-exit

# JA-3b exit gate: binding extraction (incl. the minor-mode-map poc-bug
# regression), menu-bar mining over the :filter/:enable/:visible fixture,
# and suppressed-commands unreachability.
emacs -Q --batch -L emacs -l test/jetpacs-keymap-test.el \
  -f ert-run-tests-batch-and-exit

# JA-3c/3d exit gate: imenu flatten (both index shapes), the 23.1
# exposure gates on the buffer-addressed actions, the static-candidates
# obarray guard, and the message->toast bridge's gates.
emacs -Q --batch -L emacs -l test/jetpacs-emacs-ui-test.el \
  -f ert-run-tests-batch-and-exit

# JA-6 F1 exit gate: the floor guard's :require modes driven directly
# (symlink-inside-root, path-prefix-not-component, remote-filename,
# absent-target containment), the /sdcard probe, the dired card skin's
# ordering and both caps, and the browse verbs' D1/D2 shape through the
# real dispatch.
emacs -Q --batch -L emacs -l test/jetpacs-files-test.el \
  -f ert-run-tests-batch-and-exit

# JA-6 F5 launcher exit gate: the registry read, the open verb's
# membership stale-guard, and show's :any-surface exemption.
emacs -Q --batch -L emacs -l test/jetpacs-launcher-test.el \
  -f ert-run-tests-batch-and-exit

# Cross-module seam wiring (AUDIT-ja1-ja2 3(h)): the ONLY process that
# loads the application layer together.  A seam that exists only when two
# modules are both loaded — chrome publishing itself as the navigator's
# drill host, device adding its teardown sweep — is tested by no other
# suite, so deleting it is green everywhere else.  Selector-scoped: the
# loopback harness file defines its own suite too.
emacs -Q --batch -L emacs -l test/ebp-wire-test.el -l test/jetpacs-integration-test.el \
  --eval '(ert-run-tests-batch-and-exit "^jetpacs-integration-")'

# Phase A cross-file seams + the comint P1s.  Several of these regress by
# HANGING rather than failing (a prompt reached inside a dispatch extent),
# so this suite is the one that must never be skipped.
emacs -Q --batch -L emacs -l test/jetpacs-phase-a-test.el \
  -f ert-run-tests-batch-and-exit

# The M3 Expressive Catalog (Tier-1 app) exit gate: the upstream
# inventory — 41 components, 279 examples, upstream order — plus a build
# of EVERY screen it can show, each checked for the §16.2 profile, §16.1
# id uniqueness, and canonical serialization.  Nothing else in the tree
# exercises this much of the builder surface at once.
emacs -Q --batch -L emacs -L emacs/apps/m3-catalog \
  -l test/jetpacs-m3-catalog-test.el \
  -f ert-run-tests-batch-and-exit

# Icon lint: SPEC 17.1's placeholder degrade means a misspelled icon
# never fails at runtime — this is the only gate that catches a typo.
# Ground truth is the generated docs/lookup-tables/M3-ICON-REFERENCE.org
# (regenerate with generate-icon-table.py after a dependency bump).
emacs -Q --batch -l test/jetpacs-icon-lint-test.el \
  -f ert-run-tests-batch-and-exit
