;;; jetpacs-org-vulpea-test.el --- Vulpea-arm exit gate -*- lexical-binding: t; -*-

;; The Tier-1 staging module's suite, separate from the base org suite
;; exactly as the module is separate from base.  CI has no vulpea: the
;; accessors route at a synthetic struct via cl-letf, pinning the arm's
;; documented approximations without the package.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'jetpacs-org-vulpea)

;;;; The note accessor (synthetic vulpea — CI has no vulpea)

(cl-defstruct (jetpacs-org-test-note (:constructor jetpacs-org-test-note))
  todo closed tags priority title level properties deadline scheduled
  path outline-path)

(defmacro jetpacs-org-test--as-vulpea (&rest body)
  "Route the vulpea accessors at the synthetic struct for BODY."
  `(cl-letf (((symbol-function 'vulpea-note-todo)
              #'jetpacs-org-test-note-todo)
             ((symbol-function 'vulpea-note-closed)
              #'jetpacs-org-test-note-closed)
             ((symbol-function 'vulpea-note-tags)
              #'jetpacs-org-test-note-tags)
             ((symbol-function 'vulpea-note-priority)
              #'jetpacs-org-test-note-priority)
             ((symbol-function 'vulpea-note-title)
              #'jetpacs-org-test-note-title)
             ((symbol-function 'vulpea-note-level)
              #'jetpacs-org-test-note-level)
             ((symbol-function 'vulpea-note-properties)
              #'jetpacs-org-test-note-properties)
             ((symbol-function 'vulpea-note-deadline)
              #'jetpacs-org-test-note-deadline)
             ((symbol-function 'vulpea-note-scheduled)
              #'jetpacs-org-test-note-scheduled))
     ,@body))

(ert-deftest jetpacs-org-note-accessor-semantics ()
  "The vulpea arm's documented approximations, on a synthetic note:
done-ness falls back to DONE/CLOSED; priority coerces; properties match
case-insensitively; regexp searches title+properties, NOT the body."
  (jetpacs-org-test--as-vulpea
    (let ((note (jetpacs-org-test-note
                 :todo "DONE" :closed nil :tags '("work")
                 :priority "B" :title "Call Bob" :level 1
                 :properties '(("STYLE" . "habit") ("KIND" . "call")))))
      (should (ebp-org-note-matches-p '(done) note))
      (should (ebp-org-note-matches-p '(priority "B") note))
      (should (ebp-org-note-matches-p '(property "kind" "call") note))
      (should (ebp-org-note-matches-p '(habit) note))
      ;; Title+properties haystack: hits the title...
      (should (ebp-org-note-matches-p '(regexp "Bob") note))
      ;; ...and never a body (none indexed).
      (should-not (ebp-org-note-matches-p '(regexp "body-text") note)))
    ;; CLOSED-stamp done-ness without a done keyword.
    (should (ebp-org-note-matches-p
             '(done) (jetpacs-org-test-note :closed "[2026-07-01]")))))

(ert-deftest jetpacs-org-note-query-routing ()
  (should (ebp-org-note-query-supported-p
           '(and (todo "X") (not (tags "y")))))
  (should-not (ebp-org-note-query-supported-p '(and (clocked))))
  (should (ebp-org-note-query-supported-p nil)))

;;;; The namespace (C-1)

(ert-deftest jetpacs-org-vulpea-owns-its-private-names ()
  "The arm stopped squatting the engine's private namespace.
`jetpacs-org--note-get' read as an engine internal while living in the
arm — the one file base must never require.  Renamed hard, with no
alias (house tradition: one name all the way down), so the absence is
as load-bearing as the presence.  BOTH spellings of the squat are
pinned absent: the engine's private namespace was `jetpacs-org--' when
the arm was written and is `ebp-org--' since the split, and a rename
that un-squats one only by moving into the other would be no fix at
all.  The arm's PUBLIC `ebp-org-note-*' names sit on the engine's
prefix on purpose: a second index backend implements the same two
entry points."
  (should (fboundp 'jetpacs-org-vulpea--note-get))
  (should-not (fboundp 'jetpacs-org--note-get))
  (should-not (fboundp 'ebp-org--note-get)))

(provide 'jetpacs-org-vulpea-test)
;;; jetpacs-org-vulpea-test.el ends here
