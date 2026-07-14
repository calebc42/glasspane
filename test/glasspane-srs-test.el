;;; glasspane-srs-test.el --- Tests for glasspane-srs
;;; Code:

(require 'glasspane-test-helpers)

(ert-deftest glasspane-srs-idle-view ()
  "Between sessions the view shows the due count and the start button;
zero due shows the caught-up empty state."
  (jetpacs-tests--with-fake-org-srs
    (jetpacs-org-cache-invalidate 'glasspane)
    (let* ((jetpacs-tests--srs-items '(a b c))
           (json (json-serialize
                  (jetpacs-tests--canon (glasspane-srs--view nil))
                  :null-object :null :false-object :false)))
      (should (string-search "3 items due" json))
      (should (string-search "srs.review.start" json)))
    (jetpacs-org-cache-invalidate 'glasspane)
    (let* ((jetpacs-tests--srs-items nil)
           (json (json-serialize
                  (jetpacs-tests--canon (glasspane-srs--view nil))
                  :null-object :null :false-object :false)))
      (should (string-search "All caught up" json)))))

(ert-deftest glasspane-srs-card-clean-multiline-answer ()
  "A card whose answer is a multi-line body renders the clean question
title (no stars) with the answer omitted until revealed — and NO stray
ellipsis dots (the on-device bug where each wrapped answer line showed
its own `...')."
  (jetpacs-tests--with-fake-org-srs
    (with-temp-buffer
      (org-mode)
      ;; A real entry, including org-srs's own drawers, so plain-org meta
      ;; skipping is exercised (no card-region mocks).
      (insert "* What does the Gaussian integral evaluate to?\n"
              ":PROPERTIES:\n:ID: gauss\n:END:\n"
              ":SRSITEMS:\n#+NAME: srsitem:gauss::card::back\n| ! | ts |\n:END:\n"
              "√π — a multi-line\nanswer body that\nwraps across lines.\n")
      (let ((buf (current-buffer)))
        (cl-letf (((symbol-function 'org-srs-item-marker)
                   (lambda (&rest _) (copy-marker (point-min)))))
          (let ((q (json-serialize
                    (jetpacs-tests--canon
                     (apply #'jetpacs-column
                            (glasspane-srs--item-nodes '((card back) "gauss" buf) nil)))
                    :null-object :null :false-object :false)))
            (should (string-search "Gaussian integral" q))
            (should-not (string-search "answer body" q))
            (should-not (string-search "..." q))
            (should-not (string-search "* What" q))     ; star dropped
            (should-not (string-search "SRSITEMS" q)))  ; drawer skipped
          (let ((a (json-serialize
                    (jetpacs-tests--canon
                     (apply #'jetpacs-column
                            (glasspane-srs--item-nodes '((card back) "gauss" buf) t)))
                    :null-object :null :false-object :false)))
            (should (string-search "answer body" a))
            (should (string-search "wraps across lines" a))
            (should-not (string-search "..." a))
            (should-not (string-search "SRSITEMS" a))
            ;; Flashcard prose renders proportional, not monospace.
            (should-not (string-search "mono" a))))))))

(ert-deftest glasspane-srs-card-frontback-excises-and-strips ()
  "A Front/Back card shows only the question until revealed; the
revealed answer is the Back child's body, without its heading line."
  (jetpacs-tests--with-fake-org-srs
    (with-temp-buffer
      (org-mode)
      (insert "* Term\n:PROPERTIES:\n:ID: t\n:END:\n"
              "Question text here.\n** Back\nThe answer text.\n")
      (let ((buf (current-buffer)))
        (cl-letf (((symbol-function 'org-srs-item-marker)
                   (lambda (&rest _) (copy-marker (point-min)))))
          (let ((q (json-serialize
                    (jetpacs-tests--canon
                     (apply #'jetpacs-column
                            (glasspane-srs--item-nodes '((card back) "t" buf) nil)))
                    :null-object :null :false-object :false)))
            (should (string-search "Question text" q))
            (should-not (string-search "answer text" q))
            (should-not (string-search "Back" q)))
          (let ((a (json-serialize
                    (jetpacs-tests--canon
                     (apply #'jetpacs-column
                            (glasspane-srs--item-nodes '((card back) "t" buf) t)))
                    :null-object :null :false-object :false)))
            (should (string-search "answer text" a))
            (should-not (string-search "Back" a))))))))

; heading line stripped

(ert-deftest glasspane-srs-cloze-blank-then-reveal ()
  "A cloze renders the sentence with the reviewed span blanked and the
other cloze's text as context; revealing shows the answer.  Only
`org-srs-item-cloze-collect' is mocked — bounds come from plain org."
  (jetpacs-tests--with-fake-org-srs
    (with-temp-buffer
      (org-mode)
      (insert "* The first computer bug\n:PROPERTIES:\n:ID: bug\n:END:\n"
              "operators taped {{h1}{a moth}} into the log in {{h2}{1947}}.\n")
      (let* ((buf (current-buffer))
             (c1 (progn (goto-char (point-min))
                        (search-forward "{{h1}{a moth}}")
                        (list 'h1 (match-beginning 0) (match-end 0) "a moth")))
             (c2 (progn (goto-char (point-min))
                        (search-forward "{{h2}{1947}}")
                        (list 'h2 (match-beginning 0) (match-end 0) "1947"))))
        (cl-letf (((symbol-function 'org-srs-item-marker)
                   (lambda (&rest _) (copy-marker (point-min))))
                  ((symbol-function 'org-srs-item-cloze-collect)
                   (lambda (&rest _) (list c1 c2))))
          (let ((q (json-serialize
                    (jetpacs-tests--canon
                     (apply #'jetpacs-column
                            (glasspane-srs--item-nodes '((cloze h1) "bug" buf) nil)))
                    :null-object :null :false-object :false)))
            (should (string-search "operators taped" q))
            (should (string-search "1947" q))          ; other cloze = context
            (should-not (string-search "a moth" q))    ; reviewed = blanked
            (should (string-search "[" q)))
          (let ((a (json-serialize
                    (jetpacs-tests--canon
                     (apply #'jetpacs-column
                            (glasspane-srs--item-nodes '((cloze h1) "bug" buf) t)))
                    :null-object :null :false-object :false)))
            (should (string-search "a moth" a))))))))

(ert-deftest glasspane-srs-flow-advances ()
  "The self-managed loop: start loads the first pending item; Show
answer is a pure flag (no confirm call); rating records and advances to
the next pending item; an unknown rating is ignored; a drained queue
lands on the done state; quit clears."
  (jetpacs-tests--with-fake-org-srs
    (let ((confirm-touched nil))
      (cl-letf (((symbol-function 'org-srs-item-confirm-command)
                 (lambda (&rest _) (setq confirm-touched t)))
                ((symbol-function 'org-srs-item-confirm-pending-p)
                 (lambda (&rest _) (setq confirm-touched t) nil)))
        (setq jetpacs-tests--srs-items '(((card back) "a" nil) ((card back) "b" nil)))
        (jetpacs--on-action '((action . "srs.review.start")) nil)
        (should glasspane-srs--active)
        (should (equal glasspane-srs--current '((card back) "a" nil)))
        (should-not glasspane-srs--revealed)
        ;; Show answer: pure UI flag, no org-srs confirm machinery touched.
        (jetpacs--on-action '((action . "srs.answer.show")) nil)
        (should glasspane-srs--revealed)
        (should-not confirm-touched)
        ;; Rate: records, advances to the next pending item.
        (setq jetpacs-tests--srs-items '(((card back) "b" nil)))
        (jetpacs--on-action '((action . "srs.rate") (args . ((rating . "good")))) nil)
        (should (equal jetpacs-tests--srs-rated '(:good)))
        (should (equal glasspane-srs--current '((card back) "b" nil)))
        (should-not glasspane-srs--revealed)
        ;; Unknown rating: ignored.
        (jetpacs--on-action '((action . "srs.rate") (args . ((rating . "meh")))) nil)
        (should (equal jetpacs-tests--srs-rated '(:good)))
        ;; Queue drains → done state (active, no current); quit clears.
        (setq jetpacs-tests--srs-items nil)
        (jetpacs--on-action '((action . "srs.rate") (args . ((rating . "easy")))) nil)
        (should (equal jetpacs-tests--srs-rated '(:easy :good)))
        (should-not glasspane-srs--current)
        (should glasspane-srs--active)
        (jetpacs--on-action '((action . "srs.quit")) nil)
        (should-not glasspane-srs--active)))))

(ert-deftest glasspane-srs-rate-in-item-buffer ()
  "srs.rate makes the item's buffer current before calling
`org-srs-review-rate'.  org-srs reads a session-local schedule offset
from `(current-buffer)', so rating from the wrong buffer errors and the
card never reschedules — the on-device loop."
  (jetpacs-tests--with-fake-org-srs
    (with-temp-buffer
      (let ((item-buf (current-buffer))
            (seen-buf nil))
        (cl-letf (((symbol-function 'org-srs-item-marker)
                   (lambda (&rest _)
                     (with-current-buffer item-buf (copy-marker (point-min)))))
                  ((symbol-function 'org-srs-review-rate)
                   (lambda (rating &rest _)
                     (setq seen-buf (current-buffer))
                     (push rating jetpacs-tests--srs-rated))))
          ;; Drive the action from a DIFFERENT buffer than the item's.
          (with-temp-buffer
            (setq glasspane-srs--active t
                  glasspane-srs--current (list '(card back) "id" item-buf)
                  glasspane-srs--revealed t)
            (jetpacs--on-action
             '((action . "srs.rate") (args . ((rating . "good")))) nil))
          (should (equal jetpacs-tests--srs-rated '(:good)))
          (should (eq seen-buf item-buf)))))))

(ert-deftest glasspane-srs-rate-binds-review-item ()
  "srs.rate binds `org-srs-review-item' to nil so the session-less real
`org-srs-review-rate' takes its explicit-args path instead of reading a
void variable (the on-device loop: rating errored, so the card never
rescheduled and kept reappearing)."
  (jetpacs-tests--with-fake-org-srs
    (with-temp-buffer
      (let ((item-buf (current-buffer))
            (seen 'unset))
        (cl-letf (((symbol-function 'org-srs-item-marker)
                   (lambda (&rest _)
                     (with-current-buffer item-buf (copy-marker (point-min)))))
                  ((symbol-function 'org-srs-review-rate)
                   (lambda (_rating &rest _)
                     (setq seen (if (boundp 'org-srs-review-item)
                                    org-srs-review-item 'void)))))
          (setq glasspane-srs--active t
                glasspane-srs--current (list '(card back) "a" item-buf)
                glasspane-srs--revealed t)
          (jetpacs--on-action
           '((action . "srs.rate") (args . ((rating . "good")))) nil)
          (should (eq seen nil)))))))

(ert-deftest glasspane-srs-item-create-at-ref ()
  "srs.item.create resolves the ref and runs org-srs-item-create with
the heading current (its prompts bridge to phone dialogs upstream)."
  (let ((file (make-temp-file "jetpacs-srs" nil ".org"))
        (created nil))
    (with-temp-file file (insert "* Alpha\nBody.\n* Beta\nMore.\n"))
    (unwind-protect
        (jetpacs-tests--with-fake-org-srs
          (cl-letf (((symbol-function 'org-srs-item-create)
                     (lambda ()
                       (setq created (org-get-heading t t t t)))))
            (jetpacs--on-action
             `((action . "srs.item.create")
               (args . ((file . ,file) (pos . 18)))) ; inside Beta
             nil)
            (should (equal created "Beta"))
            (should (string-search "created" (or jetpacs-shell--snackbar "")))))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

(ert-deftest glasspane-srs-detail-section-and-hook-seam ()
  "The detail splice hook carries both layers: the SRS section appears
through `glasspane-ui-detail-nodes-functions', and an erroring
contributor costs only itself."
  (jetpacs-tests--with-fake-org-srs
    (cl-letf (((symbol-function 'glasspane-ui--detail-body)
               (lambda (_ref) (jetpacs-lazy-column (jetpacs-text "The body" 'body)))))
      (let* ((glasspane-ui-detail-nodes-functions
              (list (lambda (_ref) (error "broken contributor"))
                    #'glasspane-srs-detail-nodes))
             (json (json-serialize
                    (jetpacs-tests--canon
                     (glasspane-ui--detail-body-with-notes '((id . "x"))))
                    :null-object :null :false-object :false)))
        (should (string-search "The body" json))
        (should (string-search "Make flashcard" json))
        (should (string-search "srs.item.create" json))))))

(provide 'glasspane-srs-test)
