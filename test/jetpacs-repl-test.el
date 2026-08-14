;;; jetpacs-repl-test.el --- the shared Elisp REPL -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; The loop the device home screen IS, and the catalog Playground will
;; be.  It lived in `device/init.el' and was never covered by anything:
;; the only suite that touched it extracted the hub's defuns textually
;; and asserted that the SCREEN built.  This covers the loop.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'jetpacs-repl)

(defmacro jetpacs-repl-test--session (name &rest body)
  "Run BODY with a clean session NAME, and clear it afterwards."
  (declare (indent 1))
  `(unwind-protect (progn (jetpacs-repl-clear ,name) ,@body)
     (jetpacs-repl-clear ,name)))

(ert-deftest jetpacs-repl-evaluates-every-form-like-scratch ()
  "Several forms in one input; the LAST value is the result."
  (should (= 6 (jetpacs-repl-eval-forms "(+ 1 1) (+ 2 2) (+ 3 3)")))
  (should (equal "hi" (jetpacs-repl-eval-forms "\"hi\"")))
  ;; Whitespace and comments are not forms.
  (should (= 1 (jetpacs-repl-eval-forms "  ;; a comment\n 1 \n"))))

(ert-deftest jetpacs-repl-feeds-the-last-three-values ()
  "`*' `**' `***' chain the way they do in ielm.
They are the names any Emacs user reaches for after evaluating
something, which is why they are not `jetpacs-' prefixed."
  (jetpacs-repl-eval-forms "1")
  (jetpacs-repl-eval-forms "2")
  (jetpacs-repl-eval-forms "3")
  (should (= 3 (symbol-value '*)))
  (should (= 2 (symbol-value '**)))
  (should (= 1 (symbol-value '***)))
  ;; And a follow-up expression can USE them, which is the point.
  (should (= 30 (jetpacs-repl-eval-forms "(* * 10)"))))

(ert-deftest jetpacs-repl-records-a-signal-as-a-result ()
  "A traceback is a result, not a failure — losing it is the defect."
  (jetpacs-repl-test--session "t"
    (pcase-let ((`(,value ,output ,errorp) (jetpacs-repl-run "t" "(error \"boom\")")))
      (should-not value)
      (should (string-match-p "boom" output))
      (should errorp))
    (should (= 1 (length (jetpacs-repl-history "t"))))
    ;; The loop still stands: the next form evaluates normally.
    (should (equal 3 (car (jetpacs-repl-run "t" "(+ 1 2)"))))))

(ert-deftest jetpacs-repl-sessions-do-not-share-history ()
  "Two REPLs on one device keep separate records — but ONE `*' chain."
  (jetpacs-repl-test--session "a"
    (jetpacs-repl-test--session "b"
      (jetpacs-repl-run "a" "1")
      (should (= 1 (length (jetpacs-repl-history "a"))))
      (should-not (jetpacs-repl-history "b"))
      ;; The value chain is Emacs's, not a screen's: a value yielded in
      ;; one session is reachable from the other, as between two ielms.
      (should (= 1 (car (jetpacs-repl-run "b" "*")))))))

(ert-deftest jetpacs-repl-history-is-capped ()
  (jetpacs-repl-test--session "cap"
    (let ((jetpacs-repl-history-max 3))
      (dotimes (i 10) (jetpacs-repl-record "cap" (format "%d" i) "v" nil))
      (should (= 3 (length (jetpacs-repl-history "cap"))))
      ;; Newest first.
      (should (equal "9" (car (car (jetpacs-repl-history "cap"))))))))

(ert-deftest jetpacs-repl-cards-elide-without-losing-the-record ()
  "The CARD is bounded; Copy still yields the whole value."
  (jetpacs-repl-test--session "big"
    (let* ((jetpacs-repl-output-max 10)
           (full (make-string 500 ?y)))
      (jetpacs-repl-record "big" "x" full nil)
      (let* ((json (jetpacs-node->canonical-json
                    (car (jetpacs-repl-cards "big" :verb "a.b"))))
             (runs (mapcar #'length
                           (cl-remove-if #'string-empty-p
                                         (split-string json "[^y]+")))))
        ;; Two runs of y: the elided one the card SHOWS, bounded by
        ;; `jetpacs-repl-output-max', and the whole 500 the clipboard
        ;; builtin still carries — the card is bounded, the record is not.
        (should (member jetpacs-repl-output-max runs))
        (should (member (length full) runs))))))

(ert-deftest jetpacs-repl-input-row-is-an-elisp-editor-with-a-real-button ()
  "The `.el' suffix is load-bearing and the send button is FILLED.
`ebp-complete--mode-for' matches the DOCUMENT against `auto-mode-alist'
to pick the shadow buffer's major mode, so a document id without the
suffix silently answers no completions at all — hence the signal.  And
an icon button with no variant is the container-less form, which does
not read as the primary action of a screen."
  (let ((json (jetpacs-node->canonical-json
               (jetpacs-repl-input-row :editor-id "e" :document "scratch.el"
                                       :verb "a.b"))))
    (should (string-match-p "\"syntax\":\"elisp\"" json))
    (should (string-match-p "\"complete\":true" json))
    (should (string-match-p "\"document\":\"scratch.el\"" json))
    (should (string-match-p "\"variant\":\"filled\"" json)))
  (should-error (jetpacs-repl-input-row :editor-id "e" :document "scratch"
                                        :verb "a.b")))

(ert-deftest jetpacs-repl-cards-and-empty-state-build ()
  (jetpacs-repl-test--session "s"
    (should (null (jetpacs-repl-cards "s" :verb "a.b")))
    (should (jetpacs-root-node-p (jetpacs-repl-empty-state)))
    (jetpacs-repl-record "s" "(+ 1 2)" "3" nil)
    (jetpacs-repl-record "s" "(oops" "End of file" t)
    (dolist (card (jetpacs-repl-cards "s" :verb "a.b"))
      (should (jetpacs-root-node-p card))
      (should (stringp (jetpacs-node->canonical-json card))))))

(provide 'jetpacs-repl-test)
;;; jetpacs-repl-test.el ends here
