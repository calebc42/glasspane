;;; ebp-complete-test.el --- JC-5 completion exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JC-5 exit gate (docs/PLAN-jetpacs-consumers.md, JC-5 section).
;; The harvester tests call `ebp-complete--collect' /
;; `ebp-complete-in-text' directly; the seam tests drive ebp's REAL
;; `ebp-client--handle-edit-complete' with the harvester registered, so
;; the session/seq gate, the 1201 refusal, and the reply shape are the
;; live ones, not a mock's.
;;
;; ebp-complete.el itself needs only `cl-lib'; the jetpacs and ebp-sync
;; requires below are this SUITE's — jetpacs for the one test pinning
;; `jetpacs-connect' installing the harvester through its `fboundp'
;; seam, ebp-sync for the R0 live-buffer arm, which routes through the
;; real attach table.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ebp)
(require 'ebp-sync)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'ebp-complete)

;; Interned completion targets for the elisp-capf tests: the shadow for
;; a ".el" document completes against THIS Emacs's obarray.
(defvar ebp-complete-test--needle-alpha 1)
(defvar ebp-complete-test--needle-beta 2)

(defun ebp-complete-test--labels (cands)
  (mapcar (lambda (c) (plist-get c :label)) cands))

;;;; The harvester

(ert-deftest ebp-complete-harvests-the-buffer-capf ()
  "A `.el' document's shadow runs the elisp capf against obarray.
The prefix is [capf-BEG, point) — the substring immediately before the
cursor (SPEC 19.3) — even when the capf's END extends past the cursor."
  ;; `(setq …' keeps the symbol in VARIABLE position: right after "(",
  ;; the elisp capf completes only `fboundp' symbols and the defvar'd
  ;; needles would be filtered out.  33 = the length of the seed through
  ;; "…needle-a" — it moves if the needle's NAME does, and the mid-text
  ;; case below is the one that catches a stale offset (past the end
  ;; merely clamps, which passes for the wrong reason).
  (let ((r (ebp-complete-in-text
            "notes.el" "(setq ebp-complete-test--needle-a" 33)))
    (should r)
    (should (equal (car r) "ebp-complete-test--needle-a"))
    (should (member "ebp-complete-test--needle-alpha"
                    (ebp-complete-test--labels (cdr r)))))
  ;; Cursor mid-text: the symbol continues past the cursor, the prefix
  ;; must not.
  (let ((r (ebp-complete-in-text
            "notes.el" "(setq ebp-complete-test--needle-alp)" 33)))
    (should (equal (car r) "ebp-complete-test--needle-a"))
    (should (member "ebp-complete-test--needle-alpha"
                    (ebp-complete-test--labels (cdr r)))))
  ;; Cursor clamped: past the end, and at position 0 (nothing before it).
  (should (ebp-complete-in-text
           "notes.el" "(setq ebp-complete-test--needle-a" 9999))
  ;; Position 0 also witnesses the blowout guard against the REAL
  ;; obarray: empty prefix, huge table, no fallback token.
  (should-not (ebp-complete-in-text "notes.el" "word" 0)))

(ert-deftest ebp-complete-obarray-blowout-guard ()
  "An empty prefix over an unconstrained table means EVERYTHING —
dropped by sheer size, and the word fallback finds nothing either."
  (with-temp-buffer
    (setq-local completion-at-point-functions
                (list (lambda () (list (point) (point) obarray))))
    (insert "guardword ")
    (goto-char (point-max))
    (should-not (ebp-complete--collect))))

(ert-deftest ebp-complete-empty-prefix-small-table-kept ()
  "An empty prefix on a SMALL table is legitimate member completion
\(right after a separator the source returns a precise list) — kept,
sorted shortest-first."
  (with-temp-buffer
    (setq-local completion-at-point-functions
                (list (lambda () (list (point) (point) '("alpha" "beta")))))
    (insert "obj.")
    (goto-char (point-max))
    (let ((r (ebp-complete--collect)))
      (should (equal (car r) ""))
      (should (equal (ebp-complete-test--labels (cdr r))
                     '("beta" "alpha"))))))

(ert-deftest ebp-complete-word-fallback ()
  "No capf produces anything -> words sharing the token at point, the
token itself excluded; multibyte text harvests in scalar space."
  (with-temp-buffer
    (insert "alpha beta alphabet alp")
    (goto-char (point-max))
    (let ((r (ebp-complete--collect)))
      (should (equal (car r) "alp"))
      (should (equal (ebp-complete-test--labels (cdr r))
                     '("alpha" "alphabet")))))
  (with-temp-buffer
    (insert "café caféine ca")
    (goto-char (point-max))
    (let ((r (ebp-complete--collect)))
      (should (equal (car r) "ca"))
      (should (equal (ebp-complete-test--labels (cdr r))
                     '("café" "caféine"))))))

(ert-deftest ebp-complete-annotation-insert-and-no-kind ()
  "Candidates are SPEC 19.3 closed objects: :label, trimmed :annotation,
:insert only when it differs from the label (the wire default), and the
poc's `kind' member is GONE — a closed object rejects unknown members."
  (with-temp-buffer
    (setq-local completion-at-point-functions
                (list (lambda ()
                        (list (- (point) 3) (point) '("wikilink" "wikiword")
                              :annotation-function (lambda (_) "  page  ")
                              :ebp-insert-function
                              (lambda (c) (if (equal c "wikilink")
                                              "[[id:1][wikilink]]" c))
                              :company-kind (lambda (_) 'text)))))
    (insert "wik")
    (goto-char (point-max))
    (let* ((r (ebp-complete--collect))
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

(ert-deftest ebp-complete-cap-and-sole-candidate ()
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
    (let ((ebp-complete-max-candidates 7))
      (should (= (length (cdr (ebp-complete--collect))) 7))))
  (with-temp-buffer
    (setq-local completion-at-point-functions
                (list (lambda () (list (- (point) 5) (point) '("exact")))))
    (insert "exact")
    (goto-char (point-max))
    (should-not (ebp-complete--collect))))

(ert-deftest ebp-complete-shadow-mode-and-reuse ()
  "The shadow takes its (hook-delayed) major mode from the document id,
runs the setup hook once at creation, and is reused per document; an id
matching nothing gets `fundamental-mode'."
  (let* ((witness nil)
         (ebp-complete-shadow-setup-hook
          (list (lambda () (setq witness major-mode)))))
    (let ((buf (ebp-complete--shadow-buffer "doc:src/util.py")))
      (should (eq (buffer-local-value 'major-mode buf) 'python-mode))
      (should (eq witness 'python-mode))
      ;; Reused, not rebuilt: the hook does not run again.
      (setq witness nil)
      (should (eq (ebp-complete--shadow-buffer "doc:src/util.py") buf))
      (should-not witness))
    (should (eq (buffer-local-value
                 'major-mode (ebp-complete--shadow-buffer "doc:jpick-77"))
                'fundamental-mode))))

;;;; The live-buffer arm (R0)

(defmacro ebp-complete-test--with-live-buffer (textvar &rest body)
  "Run BODY with a stub client, an attached live buffer, and the shadow
stubbed to a witness.  Binds in BODY: `client', `buf' (holding TEXTVAR,
attached as doc \"doc:r0-live.el\" / eid \"body\"), and `shadow-ran'
\(set to the marker result when the shadow arm was consulted)."
  (declare (indent 1))
  `(let* ((client (ebp-client-create
                   :receipt-file (make-temp-file "ebp-r0")))
          (buf (generate-new-buffer " *ebp-r0 live*"))
          (shadow-ran nil))
     (ignore shadow-ran)
     (unwind-protect
         (with-current-buffer buf
           (insert ,textvar)
           (puthash (cons "doc:r0-live.el" "body")
                    (list :session "S" :seq 0 :text ,textvar
                          :cursor (length ,textvar))
                    (ebp-client-editors client))
           (ebp-sync-attach client "doc:r0-live.el" "body" buf)
           (cl-letf (((symbol-function 'ebp-complete-in-text)
                      (lambda (&rest _)
                        (setq shadow-ran t)
                        (cons "sh" (list (list :label "shadow-answer"))))))
             ,@body))
       (with-current-buffer buf (ebp-sync-detach))
       (kill-buffer buf))))

(ert-deftest ebp-complete-live-buffer-arm ()
  "An attached buffer answers with ITS buffer-local capfs — the point
of R0: sources only the live buffer has (eglot's capf in real life, a
marker capf here) reach the device, and the shadow is not consulted."
  (ebp-complete-test--with-live-buffer "prefix-li"
    (setq-local completion-at-point-functions
                (list (lambda ()
                        (list (- (point) 9) (point)
                              '("prefix-live-only-needle")))))
    (let ((r (ebp-complete-edit-complete "doc:r0-live.el" "body"
                                         "prefix-li" 9)))
      (should (equal (car r) "prefix-li"))
      (should (member "prefix-live-only-needle"
                      (ebp-complete-test--labels (cdr r))))
      (should-not shadow-ran))))

(ert-deftest ebp-complete-live-arm-divergence-falls-back ()
  "Buffer text differing from the mirror TEXT means every offset would
lie (a mid-flush window) — the shadow answers from TEXT instead."
  (ebp-complete-test--with-live-buffer "prefix-li"
    (setq-local completion-at-point-functions
                (list (lambda ()
                        (list (- (point) 9) (point)
                              '("prefix-live-only-needle")))))
    (let ((r (ebp-complete-edit-complete "doc:r0-live.el" "body"
                                         "prefix-liX" 10)))
      (should shadow-ran)
      (should (equal (ebp-complete-test--labels (cdr r))
                     '("shadow-answer"))))))

(ert-deftest ebp-complete-live-arm-empty-falls-through-to-shadow ()
  "A live harvest that finds nothing lets the SHADOW answer.
`ebp-complete-shadow-setup-hook' is this module's advertised extension
point for device-document sources, and those sources exist ONLY in
shadows — an attached buffer (which never ran the hook) must not
silence them.  The R0 review caught nil-as-final doing exactly that."
  (let* ((client (ebp-client-create
                  :receipt-file (make-temp-file "ebp-r0-fall")))
         (buf (generate-new-buffer " *ebp-r0 fall*"))
         (doc "doc:r0-fall.hook")
         (ebp-complete-shadow-setup-hook
          (list (lambda ()
                  (setq-local completion-at-point-functions
                              (list (lambda ()
                                      (list (max (point-min) (- (point) 3))
                                            (point)
                                            '("zzz-hook-needle")))))))))
    (unwind-protect
        (with-current-buffer buf
          (insert "zzz")
          (puthash (cons doc "body")
                   (list :session "S" :seq 0 :text "zzz" :cursor 3)
                   (ebp-client-editors client))
          (ebp-sync-attach client doc "body" buf)
          ;; The live buffer's only capf offers exactly what is typed:
          ;; the sole-candidate rule empties the collect, and the word
          ;; fallback has nothing else in the buffer.
          (setq-local completion-at-point-functions
                      (list (lambda ()
                              (list (- (point) 3) (point) '("zzz")))))
          (let ((r (ebp-complete-edit-complete doc "body" "zzz" 3)))
            (should (member "zzz-hook-needle"
                            (ebp-complete-test--labels (cdr r))))))
      (with-current-buffer buf (ebp-sync-detach))
      (kill-buffer buf)
      (when-let* ((sb (get-buffer (format " *ebp-complete: %s*" doc))))
        (kill-buffer sb)))))

(ert-deftest ebp-complete-live-arm-is-not-reentrant ()
  "A nested `edit.complete' arriving while a live harvest waits answers
from the SHADOW.  Two stacked live harvests would share `with-timeout's
macroexpansion-minted catch tag, and the outer timer's throw would be
stolen by the inner catch, leaving the outer wait unbounded (R0
review).  The latch sends the nested request down the pre-R0 path."
  (ebp-complete-test--with-live-buffer "prefix-li"
    (let ((nested-result 'unset))
      (setq-local completion-at-point-functions
                  (list (lambda ()
                          ;; What a nested jsonrpc dispatch does
                          ;; mid-wait: ask again for the same document.
                          (when (eq nested-result 'unset)
                            (setq nested-result
                                  (ebp-complete-edit-complete
                                   "doc:r0-live.el" "body" "prefix-li" 9)))
                          (list (- (point) 9) (point)
                                '("prefix-live-only-needle")))))
      (let ((r (ebp-complete-edit-complete "doc:r0-live.el" "body"
                                           "prefix-li" 9)))
        (should (member "prefix-live-only-needle"
                        (ebp-complete-test--labels (cdr r))))
        (should (equal (ebp-complete-test--labels (cdr nested-result))
                       '("shadow-answer")))))))

(ert-deftest ebp-complete-live-arm-timeout-falls-back ()
  "A blocking live capf (an LSP server thinking) is cut off by
`ebp-complete-live-timeout' and the shadow answers.  The timeout is a
throw, so it must escape `ebp-complete--capf-data's `condition-case' —
this test fails if that wrapper ever learns to catch throws."
  (ebp-complete-test--with-live-buffer "prefix-li"
    (setq-local completion-at-point-functions
                (list (lambda ()
                        (let ((deadline (+ (float-time) 5)))
                          (while (< (float-time) deadline)
                            (accept-process-output nil 0.02)))
                        (list (- (point) 9) (point) '("never-returned")))))
    (let* ((ebp-complete-live-timeout 0.05)
           (r (ebp-complete-edit-complete "doc:r0-live.el" "body"
                                          "prefix-li" 9)))
      (should shadow-ran)
      (should (equal (ebp-complete-test--labels (cdr r))
                     '("shadow-answer"))))))

;;;; The ebp seam

(ert-deftest ebp-complete-override-beats-the-client-wide-default ()
  "ebp.el consults `ebp-client-edit-complete-overrides' before the
config's client-wide function, and only for the registered document —
the R0 shape jetpacs-dialog's picker registration relies on.  Driven
through the REAL `ebp-client--handle-edit-complete'."
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "ebp-r0-override")
                 :edit-complete-function
                 (lambda (&rest _) (cons "d" (list (list :label "default")))))))
    (dolist (doc '("doc:a" "doc:b"))
      (puthash (cons doc "e") (list :session "S" :seq 0 :text "x" :cursor 1)
               (ebp-client-editors client)))
    (puthash "doc:a"
             (lambda (&rest _) (cons "o" (list (list :label "override"))))
             (ebp-client-edit-complete-overrides client))
    (should (equal (plist-get (ebp-client--handle-edit-complete
                               client '(:document "doc:a" :editor_id "e"
                                        :session "S" :seq 0 :cursor 1))
                              :prefix)
                   "o"))
    (should (equal (plist-get (ebp-client--handle-edit-complete
                               client '(:document "doc:b" :editor_id "e"
                                        :session "S" :seq 0 :cursor 1))
                              :prefix)
                   "d"))))

(ert-deftest ebp-complete-seam-through-real-ebp-handler ()
  "The registered harvester answers ebp's real `edit.complete' handler:
live reply shape on a session/seq match, the disabled gate's empty
reply, and the stale refusal (1201) BEFORE the harvester is consulted."
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "ebp-complete-receipts")
                 :edit-complete-function #'ebp-complete-edit-complete)))
    (puthash (cons "notes.el" "body")
             (list :session "S1" :seq 4
                   :text "(setq ebp-complete-test--needle-a" :cursor 33)
             (ebp-client-editors client))
    ;; Match: the harvester's candidates come back in the wire shape.
    (let ((result (ebp-client--handle-edit-complete
                   client '(:document "notes.el" :editor_id "body"
                            :session "S1" :seq 4 :cursor 33))))
      (should (equal (plist-get result :prefix)
                     "ebp-complete-test--needle-a"))
      (should (member "ebp-complete-test--needle-alpha"
                      (ebp-complete-test--labels
                       (append (plist-get result :candidates) nil)))))
    ;; Disabled: still a reply — empty, so the device clears its dropdown.
    (let* ((ebp-complete-enabled nil)
           (result (ebp-client--handle-edit-complete
                    client '(:document "notes.el" :editor_id "body"
                             :session "S1" :seq 4 :cursor 33))))
      (should (equal (plist-get result :prefix) ""))
      (should (equal (plist-get result :candidates) [])))
    ;; Stale seq: refused by ebp before any application code runs.
    (let ((ran nil))
      (cl-letf (((symbol-function 'ebp-complete-in-text)
                 (lambda (&rest _) (setq ran t) nil)))
        (should-error (ebp-client--handle-edit-complete
                       client '(:document "notes.el" :editor_id "body"
                                :session "S1" :seq 99 :cursor 33)))
        (should-not ran)))))

(ert-deftest ebp-complete-connect-installs-the-default ()
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
                      #'ebp-complete-edit-complete))
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

(provide 'ebp-complete-test)
;;; ebp-complete-test.el ends here
