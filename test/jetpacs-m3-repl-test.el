;;; jetpacs-m3-repl-test.el --- the Catalog Playground -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; The catalog's third non-upstream section: a REPL over one sample,
;; whose print step is a rendering.  What matters here is the placement
;; rule (a duplicate `:sheet' fails SILENTLY, so it needs a pin) and the
;; blast radius of an override.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'jetpacs-m3-catalog)
(require 'jetpacs-m3-repl)

(defun jetpacs-m3-repl-test--json (id index)
  (jetpacs-node->canonical-json
   (jetpacs-m3-example-screen (jetpacs-m3-component id) index nil)))

(defmacro jetpacs-m3-repl-test--clean (&rest body)
  (declare (indent 0))
  `(unwind-protect (progn (clrhash jetpacs-m3-repl--overrides) ,@body)
     (clrhash jetpacs-m3-repl--overrides)))

(ert-deftest jetpacs-m3-repl-rides-the-sheet-when-the-slot-is-free ()
  "Every ordinary Example screen carries the Playground on its sheet."
  (let ((json (jetpacs-m3-repl-test--json "switches" 0)))
    (should (string-match-p "\"sheet\":" json))
    (should (string-match-p "\"sheet_peek_height\":96" json))
    (should (string-match-p "Playground" json))
    ;; The sheet form, not the fallback.
    (should-not (string-match-p "collapsible" json))))

(ert-deftest jetpacs-m3-repl-never-takes-a-sample-s-own-sheet ()
  "THE placement rule, and it fails silently without a pin.
`jetpacs-scaffold' is a `cl-defun', so a duplicate `:sheet' keeps the
FIRST — appending loses the Playground on these three examples and
prepending clobbers the sample they exist to demonstrate, and every gate
still passes either way.  So: Bottom Sheet's samples keep their own
sheet, and the Playground rides an in-body `collapsible' instead."
  (dolist (index '(0 1 2))
    (let* ((component (jetpacs-m3-component "bottom-sheet"))
           (example (nth index (plist-get component :examples)))
           (json (jetpacs-m3-repl-test--json "bottom-sheet" index)))
      ;; The example really does claim the slot — if this stops being
      ;; true the test is about nothing and should be rewritten.
      (should (plist-member (let ((s (plist-get example :scaffold)))
                              (if (functionp s) (funcall s) s))
                            :sheet))
      (should (string-match-p "Playground" json))
      (should (string-match-p "collapsible" json))
      (should-not (string-match-p "\"sheet_peek_height\":96" json)))))

(ert-deftest jetpacs-m3-repl-a-node-becomes-the-sample ()
  "The print step of this REPL is a rendering — that is the point."
  (jetpacs-m3-repl-test--clean
    (jetpacs-m3-repl--on-eval
     '(:component "switches" :index 0 :value "(jetpacs-text \"ZZTOP\")") nil)
    (sit-for 0.2)
    (should (equal '(:t "text" :text "ZZTOP")
                   (jetpacs-m3-repl-override "switches" 0)))
    (should (string-match-p "ZZTOP" (jetpacs-m3-repl-test--json "switches" 0)))
    ;; And Reset gives upstream's sample back.
    (should (eq 'accepted (jetpacs-m3-repl--on-reset
                           '(:component "switches" :index 0) nil)))
    (should-not (jetpacs-m3-repl-override "switches" 0))
    (should (string-match-p "\"t\":\"switch\""
                            (jetpacs-m3-repl-test--json "switches" 0)))))

(ert-deftest jetpacs-m3-repl-a-failed-experiment-costs-nothing ()
  "A non-node value stays a card; an ERROR never touches the sample.
The screen you were looking at is the one thing a bad form must not
take from you."
  (jetpacs-m3-repl-test--clean
    (dolist (input '("(+ 1 2)" "(error \"boom\")" "\"just a string\""))
      (jetpacs-m3-repl--on-eval
       (list :component "switches" :index 0 :value input) nil)
      (sit-for 0.2))
    (should-not (jetpacs-m3-repl-override "switches" 0))
    (should (string-match-p "\"t\":\"switch\""
                            (jetpacs-m3-repl-test--json "switches" 0)))))

(ert-deftest jetpacs-m3-repl-an-override-cannot-leak-sideways ()
  "Keyed per example, so a sibling and a neighbouring component are
untouched — and `jetpacs-m3-repl-reset-all' clears the lot."
  (jetpacs-m3-repl-test--clean
    (jetpacs-m3-repl--on-eval
     '(:component "switches" :index 0 :value "(jetpacs-text \"ONLY-HERE\")") nil)
    (sit-for 0.2)
    (should (jetpacs-m3-repl-override "switches" 0))
    (should-not (jetpacs-m3-repl-override "switches" 1))
    (should-not (jetpacs-m3-repl-override "buttons" 0))
    (should-not (string-match-p "ONLY-HERE" (jetpacs-m3-repl-test--json "switches" 1)))
    (jetpacs-m3-repl-reset-all)
    (should-not (jetpacs-m3-repl-override "switches" 0))))

(ert-deftest jetpacs-m3-repl-verbs-refuse-what-they-cannot-address ()
  (should (eq 'stale (jetpacs-m3-repl--on-eval
                      '(:component "nope" :index 0 :value "1") nil)))
  (should (eq 'stale (jetpacs-m3-repl--on-eval
                      '(:component "switches" :index 99 :value "1") nil)))
  (should (eq 'rejected (jetpacs-m3-repl--on-eval
                         '(:component "switches" :index "0" :value "1") nil)))
  ;; No value and no live client: nothing to evaluate.
  (should (eq 'rejected (jetpacs-m3-repl--on-eval
                         '(:component "switches" :index 0) nil)))
  (should (eq 'stale (jetpacs-m3-repl--on-reset
                      '(:component "nope" :index 0) nil))))

(ert-deftest jetpacs-m3-repl-seeds-the-prompt-with-the-sample ()
  "The field opens holding the thing it is about.
An empty box over a vocabulary you do not know yet is not a REPL you can
start using."
  (let ((seed (jetpacs-m3-repl--seed (jetpacs-m3-component "switches") 0)))
    (should (string-prefix-p "(defun jetpacs-m3-switches--" seed))
    (should (string-match-p "Upstream SwitchSample" seed)))
  ;; The document and editor ids are per example, so a half-typed form
  ;; cannot follow you into the next one.
  (should-not (equal (jetpacs-m3-repl-document "switches" 0)
                     (jetpacs-m3-repl-document "switches" 1)))
  (should (string-suffix-p ".el" (jetpacs-m3-repl-document "switches" 0))))

(provide 'jetpacs-m3-repl-test)
;;; jetpacs-m3-repl-test.el ends here
