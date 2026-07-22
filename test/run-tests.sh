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

emacs -Q --batch -L emacs -l test/ebp-wire-test.el \
  -f ert-run-tests-batch-and-exit
