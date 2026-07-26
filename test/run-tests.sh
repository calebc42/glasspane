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

# Same guard for the application-layer widget builders.
emacs -Q --batch -L emacs \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile emacs/jetpacs-widgets.el
rm -f emacs/jetpacs-widgets.elc

# And for the JC-0 application-framework floor (docs/SPEC-JC-0-floor.md)
# plus the JC-1 Tier-0 buffer renderer.
for f in jetpacs-async jetpacs-surfaces jetpacs-shell jetpacs-buffer \
         jetpacs-results jetpacs-tablist \
         jetpacs-sections jetpacs-comint jetpacs-hypertext \
         jetpacs-dialog jetpacs-complete jetpacs-theme jetpacs-device \
         jetpacs-clip; do
  emacs -Q --batch -L emacs \
    --eval '(setq byte-compile-error-on-warn t)' \
    -f batch-byte-compile "emacs/$f.el"
  rm -f "emacs/$f.elc"
done

emacs -Q --batch -L emacs -l test/ebp-wire-test.el \
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

# Phase A cross-file seams + the comint P1s.  Several of these regress by
# HANGING rather than failing (a prompt reached inside a dispatch extent),
# so this suite is the one that must never be skipped.
emacs -Q --batch -L emacs -l test/jetpacs-phase-a-test.el \
  -f ert-run-tests-batch-and-exit
