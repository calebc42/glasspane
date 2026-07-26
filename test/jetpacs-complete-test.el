;;; jetpacs-complete-test.el --- JC-5 completion exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JC-5 exit gate (docs/PLAN-jetpacs-consumers.md, JC-5 section).
;; The harvester tests call `jetpacs-complete--collect' /
;; `jetpacs-complete-in-text' directly; the seam tests drive ebp's REAL
;; `ebp-client--handle-edit-complete' with the harvester registered, so
;; the session/seq gate, the 1201 refusal, and the reply shape are the
;; live ones, not a mock's.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-complete)

;; Interned completion targets for the elisp-capf tests: the shadow for
;; a ".el" document completes against THIS Emacs's obarray.
(defvar jetpacs-complete-test--needle-alpha 1)
(defvar jetpacs-complete-test--needle-beta 2)

(defun jetpacs-complete-test--labels (cands)
  (mapcar (lambda (c) (plist-get c :label)) cands))

;;;; The harvester

(ert-deftest jetpacs-complete-harvests-the-buffer-capf ()
  "A `.el' document's shadow runs the elisp capf against obarray.
The prefix is [capf-BEG, point) — the substring immediately before the
cursor (SPEC 19.3) — even when the capf's END extends past the cursor."
  ;; `(setq …' keeps the symbol in VARIABLE position: right after "(",
  ;; the elisp capf completes only `fboundp' symbols and the defvar'd
  ;; needles would be filtered out.
  (let ((r (jetpacs-complete-in-text
            "notes.el" "(setq jetpacs-complete-test--needle-a" 37)))
    (should r)
    (should (equal (car r) "jetpacs-complete-test--needle-a"))
    (should (member "jetpacs-complete-test--needle-alpha"
                    (jetpacs-complete-test--labels (cdr r)))))
  ;; Cursor mid-text: the symbol continues past the cursor, the prefix
  ;; must not.
  (let ((r (jetpacs-complete-in-text
            "notes.el" "(setq jetpacs-complete-test--needle-alp)" 37)))
    (should (equal (car r) "jetpacs-complete-test--needle-a"))
    (should (member "jetpacs-complete-test--needle-alpha"
                    (jetpacs-complete-test--labels (cdr r)))))
  ;; Cursor clamped: past the end, and at position 0 (nothing before it).
  (should (jetpacs-complete-in-text
           "notes.el" "(setq jetpacs-complete-test--needle-a" 9999))
  ;; Position 0 also witnesses the blowout guard against the REAL
  ;; obarray: empty prefix, huge table, no fallback token.
  (should-not (jetpacs-complete-in-text "notes.el" "word" 0)))

(ert-deftest jetpacs-complete-obarray-blowout-guard ()
  "An empty prefix over an unconstrained table means EVERYTHING —
dropped by sheer size, and the word fallback finds nothing either."
  (with-temp-buffer
    (setq-local completion-at-point-functions
                (list (lambda () (list (point) (point) obarray))))
    (insert "guardword ")
    (goto-char (point-max))
    (should-not (jetpacs-complete--collect))))

(ert-deftest jetpacs-complete-empty-prefix-small-table-kept ()
  "An empty prefix on a SMALL table is legitimate member completion
\(right after a separator the source returns a precise list) — kept,
sorted shortest-first."
  (with-temp-buffer
    (setq-local completion-at-point-functions
                (list (lambda () (list (point) (point) '("alpha" "beta")))))
    (insert "obj.")
    (goto-char (point-max))
    (let ((r (jetpacs-complete--collect)))
      (should (equal (car r) ""))
      (should (equal (jetpacs-complete-test--labels (cdr r))
                     '("beta" "alpha"))))))

(ert-deftest jetpacs-complete-word-fallback ()
  "No capf produces anything -> words sharing the token at point, the
token itself excluded; multibyte text harvests in scalar space."
  (with-temp-buffer
    (insert "alpha beta alphabet alp")
    (goto-char (point-max))
    (let ((r (jetpacs-complete--collect)))
      (should (equal (car r) "alp"))
      (should (equal (jetpacs-complete-test--labels (cdr r))
                     '("alpha" "alphabet")))))
  (with-temp-buffer
    (insert "café caféine ca")
    (goto-char (point-max))
    (let ((r (jetpacs-complete--collect)))
      (should (equal (car r) "ca"))
      (should (equal (jetpacs-complete-test--labels (cdr r))
                     '("café" "caféine"))))))

(ert-deftest jetpacs-complete-annotation-insert-and-no-kind ()
  "Candidates are SPEC 19.3 closed objects: :label, trimmed :annotation,
:insert only when it differs from the label (the wire default), and the
poc's `kind' member is GONE — a closed object rejects unknown members."
  (with-temp-buffer
    (setq-local completion-at-point-functions
                (list (lambda ()
                        (list (- (point) 3) (point) '("wikilink" "wikiword")
                              :annotation-function (lambda (_) "  page  ")
                              :jetpacs-insert-function
                              (lambda (c) (if (equal c "wikilink")
                                              "[[id:1][wikilink]]" c))
                              :company-kind (lambda (_) 'text)))))
    (insert "wik")
    (goto-char (point-max))
    (let* ((r (jetpacs-complete--collect))
           (c1 (car (cdr r)))
           (c2 (cadr (cdr r))))
      (should (equal (car r) "wik"))
      (should (equal (plist-get c1 :label) "wikilink"))
      (should (equal (plist-get c1 :annotation) "page"))
      (should (equal (plist-get c1 :insert) "[[id:1][wikilink]]"))
      (should (equal (plist-get c2 :label) "wikiword"))
      (should-not (plist-member c2 :insert))
      (should-not (plist-member c1 :kind))
      (should-not (plist-member c2 :kind)))))

(ert-deftest jetpacs-complete-cap-and-sole-candidate ()
  "The candidate list is capped, and a sole candidate equal to what is
already typed offers nothing."
  (with-temp-buffer
    (setq-local completion-at-point-functions
                (list (lambda ()
                        (list (- (point) 2) (point)
                              (cl-loop for i below 80
                                       collect (format "ca-%02d" i))))))
    (insert "ca")
    (goto-char (point-max))
    (let ((jetpacs-complete-max-candidates 7))
      (should (= (length (cdr (jetpacs-complete--collect))) 7))))
  (with-temp-buffer
    (setq-local completion-at-point-functions
                (list (lambda () (list (- (point) 5) (point) '("exact")))))
    (insert "exact")
    (goto-char (point-max))
    (should-not (jetpacs-complete--collect))))

(ert-deftest jetpacs-complete-shadow-mode-and-reuse ()
  "The shadow takes its (hook-delayed) major mode from the document id,
runs the setup hook once at creation, and is reused per document; an id
matching nothing gets `fundamental-mode'."
  (let* ((witness nil)
         (jetpacs-complete-shadow-setup-hook
          (list (lambda () (setq witness major-mode)))))
    (let ((buf (jetpacs-complete--shadow-buffer "doc:src/util.py")))
      (should (eq (buffer-local-value 'major-mode buf) 'python-mode))
      (should (eq witness 'python-mode))
      ;; Reused, not rebuilt: the hook does not run again.
      (setq witness nil)
      (should (eq (jetpacs-complete--shadow-buffer "doc:src/util.py") buf))
      (should-not witness))
    (should (eq (buffer-local-value
                 'major-mode (jetpacs-complete--shadow-buffer "doc:jpick-77"))
                'fundamental-mode))))

;;;; The ebp seam

(ert-deftest jetpacs-complete-seam-through-real-ebp-handler ()
  "The registered harvester answers ebp's real `edit.complete' handler:
live reply shape on a session/seq match, the disabled gate's empty
reply, and the stale refusal (1201) BEFORE the harvester is consulted."
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jetpacs-complete-receipts")
                 :edit-complete-function #'jetpacs-complete-edit-complete)))
    (puthash (cons "notes.el" "body")
             (list :session "S1" :seq 4
                   :text "(setq jetpacs-complete-test--needle-a" :cursor 37)
             (ebp-client-editors client))
    ;; Match: the harvester's candidates come back in the wire shape.
    (let ((result (ebp-client--handle-edit-complete
                   client '(:document "notes.el" :editor_id "body"
                            :session "S1" :seq 4 :cursor 37))))
      (should (equal (plist-get result :prefix)
                     "jetpacs-complete-test--needle-a"))
      (should (member "jetpacs-complete-test--needle-alpha"
                      (jetpacs-complete-test--labels
                       (append (plist-get result :candidates) nil)))))
    ;; Disabled: still a reply — empty, so the device clears its dropdown.
    (let* ((jetpacs-complete-enabled nil)
           (result (ebp-client--handle-edit-complete
                    client '(:document "notes.el" :editor_id "body"
                             :session "S1" :seq 4 :cursor 37))))
      (should (equal (plist-get result :prefix) ""))
      (should (equal (plist-get result :candidates) [])))
    ;; Stale seq: refused by ebp before any application code runs.
    (let ((ran nil))
      (cl-letf (((symbol-function 'jetpacs-complete-in-text)
                 (lambda (&rest _) (setq ran t) nil)))
        (should-error (ebp-client--handle-edit-complete
                       client '(:document "notes.el" :editor_id "body"
                                :session "S1" :seq 99 :cursor 37)))
        (should-not ran)))))

(ert-deftest jetpacs-complete-connect-installs-the-default ()
  "`jetpacs-connect' wires the harvester as the client-wide completion
answer when the caller supplied nothing; an explicit value wins."
  (cl-letf (((symbol-function 'ebp-connect)
             (lambda (_host _port &rest config)
               (apply #'ebp-client-create config))))
    (let ((client (jetpacs-connect
                   "127.0.0.1" 0
                   :receipt-file (make-temp-file "jc5-connect-a"))))
      (unwind-protect
          (should (eq (plist-get (ebp-client-config client)
                                 :edit-complete-function)
                      #'jetpacs-complete-edit-complete))
        (jetpacs-detach) (jetpacs-test-reset-state)))
    (let ((client (jetpacs-connect
                   "127.0.0.1" 0
                   :receipt-file (make-temp-file "jc5-connect-b")
                   :edit-complete-function #'ignore)))
      (unwind-protect
          (should (eq (plist-get (ebp-client-config client)
                                 :edit-complete-function)
                      #'ignore))
        (jetpacs-detach) (jetpacs-test-reset-state)))))

(provide 'jetpacs-complete-test)
;;; jetpacs-complete-test.el ends here
