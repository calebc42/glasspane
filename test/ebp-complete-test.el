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
:insert only when it differs from the label (the wire default) — and
`kind' stays OMITTED on an ungated harvest even when the capf offers
`:company-kind': since #169 the member exists but is feature-gated,
and this collect ran with no registration (the sender-omit default)."
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

;;;; Candidate `kind' (amendment #169, R3)

(ert-deftest ebp-complete-kind-vocabulary-matches-the-contract ()
  "The elisp vocabulary IS the contract's `candidate_schema.kind_enum'
— the cross-implementation pin; drift on either side fails here."
  (let* ((contract (json-parse-string
                    (with-temp-buffer
                      (insert-file-contents
                       (expand-file-name "ebp/contract.json"))
                      (buffer-string))
                    :object-type 'alist :array-type 'list))
         (enum (alist-get 'kind_enum
                          (alist-get 'candidate_schema contract))))
    (should enum)
    (should (equal (sort (copy-sequence enum) #'string<)
                   (sort (copy-sequence ebp-complete-kind-vocabulary)
                         #'string<)))))

(ert-deftest ebp-complete-kind-emitted-when-registered ()
  "A registered editor's replies carry `kind' from capf
`:company-kind', resolved against the RAW candidate (eglot's kind
rides text properties the wire strip removes) and FILTERED to the
registered vocabulary — a backend's unregistered spelling is omitted,
never sent."
  (unwind-protect
      (with-temp-buffer
        (setq-local completion-at-point-functions
                    (list (lambda ()
                            (list (- (point) 3) (point)
                                  (list (propertize "printing"
                                                    'ebp-r3-kind 'function)
                                        (propertize "priority"
                                                    'ebp-r3-kind 'bogus-kind))
                                  :company-kind
                                  (lambda (c)
                                    (get-text-property 0 'ebp-r3-kind c))))))
        (insert "pri")
        (goto-char (point-max))
        (ebp-complete-set-editor-kinds "doc:r3.el" "body" t)
        (let* ((ebp-complete--emit-kinds
                (gethash (cons "doc:r3.el" "body")
                         ebp-complete--kind-editors))
               (r (ebp-complete--collect))
               (printing (cl-find "printing" (cdr r)
                                  :key (lambda (c) (plist-get c :label))
                                  :test #'equal))
               (priority (cl-find "priority" (cdr r)
                                  :key (lambda (c) (plist-get c :label))
                                  :test #'equal)))
          ;; The propertized twin carried the kind through the strip.
          (should (equal (plist-get printing :kind) "function"))
          ;; The unregistered spelling is filtered, not forwarded.
          (should-not (plist-member priority :kind))))
    (ebp-complete-set-editor-kinds "doc:r3.el" "body" nil)))

(ert-deftest ebp-complete-kind-omitted-by-default ()
  "THE sender-omit pin: an UNREGISTERED editor's replies never carry
`kind', whatever the capf offers — absent registration is the
conforming default, and the seam binds the gate from the registry."
  (with-temp-buffer
    (setq-local completion-at-point-functions
                (list (lambda ()
                        (list (- (point) 3) (point) '("printing")
                              :company-kind (lambda (_) 'function)))))
    (insert "pri")
    (goto-char (point-max))
    ;; Through the REAL seam, whose let binds the gate from the registry.
    (cl-letf (((symbol-function 'ebp-complete--live-harvest)
               (lambda (&rest _) nil))
              ((symbol-function 'ebp-complete-in-text)
               (let ((buf (current-buffer)))
                 (lambda (&rest _)
                   (with-current-buffer buf (ebp-complete--collect))))))
      (let ((r (ebp-complete-edit-complete "doc:r3-unreg.el" "body"
                                           "pri" 3)))
        (should r)
        (should-not (plist-member (car (cdr r)) :kind))))))

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

;;;; The accept loop (R2)

(defmacro ebp-complete-test--with-accept-setup (&rest body)
  "A live attached buffer \"prefix-li\" whose capf carries an
`:exit-function'.  Binds client, buf, sent (captured requests),
exit-calls (each: (STRING PROP STATUS POINT))."
  (declare (indent 0))
  `(let* ((client (ebp-client-create :receipt-file (make-temp-file "r2")))
          (buf (generate-new-buffer " *r2 accept*"))
          (sent nil) (exit-calls nil))
     (ignore sent exit-calls)
     (unwind-protect
         (with-current-buffer buf
           (insert "prefix-li")
           (puthash (cons "doc:r2.el" "body")
                    (list :session "S" :seq 0 :text "prefix-li" :cursor 9)
                    (ebp-client-editors client))
           (ebp-sync-attach client "doc:r2.el" "body" buf)
           (setq-local completion-at-point-functions
                       (list (lambda ()
                               (list (- (point) 9) (point)
                                     (list (propertize "prefix-live-needle"
                                                       'ebp-r2-item 'yes))
                                     :exit-function
                                     (lambda (s status)
                                       (push (list (substring-no-properties s)
                                                   (get-text-property
                                                    0 'ebp-r2-item s)
                                                   status (point)
                                                   (bound-and-true-p
                                                    ebp-complete--live-harvest-active))
                                             exit-calls)
                                       ;; The auto-import shape: a
                                       ;; distant edit far from the
                                       ;; completion.
                                       (save-excursion
                                         (goto-char (point-min))
                                         (insert ";; import\n")))))))
           (cl-letf (((symbol-function 'ebp-client--request)
                      (lambda (_c method params cb &optional _t)
                        (push (list method params cb) sent))))
             ,@body))
       (setq ebp-complete-live-offer nil)
       (with-current-buffer buf (ebp-sync-detach))
       (kill-buffer buf))))

(ert-deftest ebp-complete-accept-runs-the-exit-function ()
  "The R2 accept loop end to end through ebp's REAL handlers: a live
harvest with an `:exit-function' capf mints the offer; the accept
arrives as an ORDINARY `edit.delta' (the wire marks nothing); the exit
function runs DEFERRED in the real buffer — with the PROPERTIZED
candidate, `finished', and point after the completed text — and a
distant edit it makes (auto-import) flushes back as ordinary
`edit.apply' traffic.  No SPEC change anywhere in this loop."
  (ebp-complete-test--with-accept-setup
    (let ((r (ebp-complete-edit-complete "doc:r2.el" "body" "prefix-li" 9)))
      (should (member "prefix-live-needle"
                      (ebp-complete-test--labels (cdr r)))))
    (should ebp-complete-live-offer)
    (ebp-client--handle-edit-delta
     client (list :document "doc:r2.el" :editor_id "body" :session "S"
                  :seq 1 :start 0 :del 9 :text "prefix-live-needle"
                  :len 18))
    (should (equal (buffer-string) "prefix-live-needle"))
    ;; Deferred: nothing ran inside the dispatch extent.
    (should-not exit-calls)
    (should-not ebp-complete-live-offer)
    (cl-loop repeat 30 until exit-calls
             do (accept-process-output nil 0.02))
    (pcase-let ((`(,s ,item ,status ,pt ,guarded) (car exit-calls)))
      (should (equal s "prefix-live-needle"))
      (should (eq item 'yes))             ; text properties survived
      (should (eq status 'finished))
      (should (= pt 19))                  ; right after the completion
      ;; The R0 guards cover this blocking extent too: a nested
      ;; edit.complete would take the shadow, and flow continuations
      ;; defer off the timeout throw's unwind path.
      (should guarded))
    (ebp-sync-flush buf)
    (let ((apply-frame (cl-find 'edit.apply sent :key #'car)))
      (should apply-frame)
      (should (= (plist-get (nth 1 apply-frame) :start) 0))
      (should (equal (plist-get (nth 1 apply-frame) :text) ";; import\n")))))

(ert-deftest ebp-complete-accept-mismatch-clears-the-offer ()
  "R4 semantics: a caret insertion EXTENDS the offer (the #171
qualifying splice) instead of clearing it — and once any extension is
tracked, the unmarked R2 shape heuristic is DEAD (pin 4): a later
accept-shaped UNMARKED splice claims the offer without firing, because
extension survival must not widen the unmarked inference surface.  A
deletion still claims outright."
  (ebp-complete-test--with-accept-setup
    (ebp-complete-edit-complete "doc:r2.el" "body" "prefix-li" 9)
    (should ebp-complete-live-offer)
    ;; The user types at the caret: a QUALIFYING extension — survives.
    (ebp-client--handle-edit-delta
     client (list :document "doc:r2.el" :editor_id "body" :session "S"
                  :seq 1 :start 9 :del 0 :text "x" :len 10))
    (should ebp-complete-live-offer)
    (should (= (plist-get ebp-complete-live-offer :ext) 1))
    ;; The exact R2 accept shape — del = ORIGINAL prefix length, start
    ;; at its left edge, shared first scalar — UNMARKED, after an
    ;; extension: pin 4 — the pristine heuristic never fires once
    ;; ext > 0; claimed, no run.  (del 9, not 10: the R2 shape, which a
    ;; pin-4 mutant would wrongly finish.)
    (ebp-client--handle-edit-delta
     client (list :document "doc:r2.el" :editor_id "body" :session "S"
                  :seq 2 :start 0 :del 9 :text "prefix-live-needle"
                  :len 19))
    (should-not ebp-complete-live-offer)
    (cl-loop repeat 10 do (accept-process-output nil 0.02))
    (should-not exit-calls)
    ;; And a deletion claims a fresh offer outright (never qualifying).
    (puthash (cons "doc:r2.el" "body")
             (list :session "S" :seq 2 :text (with-current-buffer buf
                                               (buffer-string))
                   :cursor 9)
             (ebp-client-editors client))
    (ebp-complete-edit-complete "doc:r2.el" "body"
                                (with-current-buffer buf (buffer-string)) 9)
    (when ebp-complete-live-offer
      (ebp-client--handle-edit-delta
       client (list :document "doc:r2.el" :editor_id "body" :session "S"
                    :seq 3 :start 8 :del 1 :text ""
                    :len (1- (with-current-buffer buf
                               (length (buffer-string))))))
      (should-not ebp-complete-live-offer))))

(ert-deftest ebp-complete-marked-accept-validates-by-membership ()
  "The #170 marked arm: a delta carrying `accept: true' runs the exit
function on MEMBERSHIP and REGION alone — this candidate shares
NEITHER end scalar with the prefix (the flex shape the unmarked
heuristic must refuse), and with the marker it finishes."
  (let* ((client (ebp-client-create :receipt-file (make-temp-file "r4")))
         (buf (generate-new-buffer " *r4 marked*"))
         (exit-calls nil))
    (unwind-protect
        (with-current-buffer buf
          (insert "li")
          (puthash (cons "doc:r4.el" "body")
                   (list :session "S" :seq 0 :text "li" :cursor 2)
                   (ebp-client-editors client))
          (ebp-sync-attach client "doc:r4.el" "body" buf)
          (setq-local completion-at-point-functions
                      (list (lambda ()
                              (list (- (point) 2) (point)
                                    (lambda (str pred action)
                                      (if (eq action t) '("XyzQw")
                                        (complete-with-action
                                         action '("XyzQw") str pred)))
                                    :exit-function
                                    (lambda (&rest args)
                                      (push args exit-calls))))))
          (ebp-complete-edit-complete "doc:r4.el" "body" "li" 2)
          (should ebp-complete-live-offer)
          ;; Negative first: marked but NON-MEMBER text — claimed, no
          ;; run (membership is the marked arm's whole validation).
          (ebp-client--handle-edit-delta
           client (list :document "doc:r4.el" :editor_id "body"
                        :session "S" :seq 1 :start 0 :del 2 :text "Rogue"
                        :len 5 :accept t))
          (should-not ebp-complete-live-offer)
          (cl-loop repeat 5 do (accept-process-output nil 0.02))
          (should-not exit-calls)
          ;; The delta APPLIED regardless (a real splice): buffer now
          ;; "Rogue".  Negative second: member text but WRONG del (the
          ;; region check).  Mint against the current state.
          (ebp-complete-edit-complete "doc:r4.el" "body" "Rogue" 2)
          (should ebp-complete-live-offer)
          (ebp-client--handle-edit-delta
           client (list :document "doc:r4.el" :editor_id "body"
                        :session "S" :seq 2 :start 1 :del 1 :text "XyzQw"
                        :len 9 :accept t))
          (should-not ebp-complete-live-offer)
          (cl-loop repeat 5 do (accept-process-output nil 0.02))
          (should-not exit-calls)
          ;; The positive: reset to "li" BY HAND (consume the tracker —
          ;; a manual buffer edit otherwise poisons the queue and the
          ;; next splice resyncs instead of dispatching), re-mint, then
          ;; the flex-shape member marked — finishes.
          (with-current-buffer buf
            (delete-region (point-min) (point-max))
            (insert "li")
            (save-restriction
              (widen)
              (track-changes-fetch ebp-sync--tracker #'ignore)))
          (puthash (cons "doc:r4.el" "body")
                   (list :session "S" :seq 2 :text "li" :cursor 2)
                   (ebp-client-editors client))
          (ebp-complete-edit-complete "doc:r4.el" "body" "li" 2)
          (should ebp-complete-live-offer)
          (ebp-client--handle-edit-delta
           client (list :document "doc:r4.el" :editor_id "body"
                        :session "S" :seq 3 :start 0 :del 2 :text "XyzQw"
                        :len 5 :accept t))
          (should-not ebp-complete-live-offer)
          (cl-loop repeat 30 until exit-calls
                   do (accept-process-output nil 0.02))
          (should exit-calls))
      (setq ebp-complete-live-offer nil)
      (with-current-buffer buf (ebp-sync-detach))
      (kill-buffer buf))))

(ert-deftest ebp-complete-marked-accept-spans-the-extension ()
  "The full #171 loop: a qualifying extension grows the tracked region,
and the marked accept replaces prefix-plus-extension — the region
arithmetic of corollary pin 2."
  (ebp-complete-test--with-accept-setup
    (ebp-complete-edit-complete "doc:r2.el" "body" "prefix-li" 9)
    ;; Type "v": qualifying (del 0 at region end 9).
    (ebp-client--handle-edit-delta
     client (list :document "doc:r2.el" :editor_id "body" :session "S"
                  :seq 1 :start 9 :del 0 :text "v" :len 10))
    (should (= (plist-get ebp-complete-live-offer :ext) 1))
    ;; The marked accept spans prefix (9) + extension (1) = del 10 at 0.
    (ebp-client--handle-edit-delta
     client (list :document "doc:r2.el" :editor_id "body" :session "S"
                  :seq 2 :start 0 :del 10 :text "prefix-live-needle"
                  :len 18 :accept t))
    (should-not ebp-complete-live-offer)
    (cl-loop repeat 30 until exit-calls
             do (accept-process-output nil 0.02))
    (pcase-let ((`(,s ,item ,status ,_pt ,_g) (car exit-calls)))
      (should (equal s "prefix-live-needle"))
      (should (eq item 'yes))
      (should (eq status 'finished)))))

(ert-deftest ebp-complete-accept-ambiguous-shape-never-fires ()
  "Provenance by shape (R2 review): a splice whose deleted prefix and
inserted text share NEITHER end scalar is exactly what paste,
swipe-typing, and IME word commits produce — the Companion's minimal
diff would have trimmed a shared end — so it must never run an exit
function, even though a flex-matched tap could produce it too.
Missing that rare tap is the safe direction."
  (let* ((client (ebp-client-create :receipt-file (make-temp-file "r2a")))
         (buf (generate-new-buffer " *r2 ambiguous*"))
         (exit-calls nil))
    (unwind-protect
        (with-current-buffer buf
          (insert "li")
          (puthash (cons "doc:r2a.el" "body")
                   (list :session "S" :seq 0 :text "li" :cursor 2)
                   (ebp-client-editors client))
          (ebp-sync-attach client "doc:r2a.el" "body" buf)
          ;; A flex-style FUNCTION table (eglot's shape): it matches
          ;; "XyzQw" against "li" itself — a plain list table would
          ;; prefix-filter the candidate away and no offer would mint.
          (setq-local completion-at-point-functions
                      (list (lambda ()
                              (list (- (point) 2) (point)
                                    (lambda (str pred action)
                                      (if (eq action t) '("XyzQw")
                                        (complete-with-action
                                         action '("XyzQw") str pred)))
                                    :exit-function
                                    (lambda (&rest args)
                                      (push args exit-calls))))))
          (ebp-complete-edit-complete "doc:r2a.el" "body" "li" 2)
          (should ebp-complete-live-offer)
          ;; The accept SHAPE — but "XyzQw" shares neither 'l' nor 'i'
          ;; with the prefix, so it could be a paste.  Never fires.
          (ebp-client--handle-edit-delta
           client (list :document "doc:r2a.el" :editor_id "body"
                        :session "S" :seq 1 :start 0 :del 2 :text "XyzQw"
                        :len 5))
          (should-not ebp-complete-live-offer)
          (cl-loop repeat 10 do (accept-process-output nil 0.02))
          (should-not exit-calls))
      (setq ebp-complete-live-offer nil)
      (with-current-buffer buf (ebp-sync-detach))
      (kill-buffer buf))))

(ert-deftest ebp-complete-accept-offer-lifecycle-claims ()
  "Session lifecycle boundaries claim the offer (R2 review): a reseed
replaces the text its coordinates described, and detach ends the
session it belonged to."
  (ebp-complete-test--with-accept-setup
    (ebp-complete-edit-complete "doc:r2.el" "body" "prefix-li" 9)
    (should ebp-complete-live-offer)
    ;; A reseed (fresh session / post-resync edit.open).
    (ebp-client--handle-edit-open
     client (list :document "doc:r2.el" :editor_id "body"
                  :session "T" :seq 0 :text "other" :cursor 0))
    (should-not ebp-complete-live-offer)
    ;; Re-mint, then detach.
    (puthash (cons "doc:r2.el" "body")
             (list :session "T" :seq 0 :text (buffer-string)
                   :cursor 5)
             (ebp-client-editors client))
    (ebp-complete-edit-complete "doc:r2.el" "body" (buffer-string) 5)
    (when ebp-complete-live-offer
      (ebp-sync-detach buf)
      (should-not ebp-complete-live-offer))))

(ert-deftest ebp-complete-accept-rearm-on-latch ()
  "A runner arriving while another exit function is on the stack
RE-ARMS instead of dropping (R2 review) — the second completion's
auto-import must not silently vanish — and the re-arm is capped."
  (let ((buf (generate-new-buffer " *r2 rearm*"))
        (scheduled nil))
    (unwind-protect
        (cl-letf (((symbol-function 'run-at-time)
                   (lambda (&rest args) (push args scheduled))))
          (let ((ebp-sync--exit-fn-running t))
            (ebp-sync--run-exit-fn buf 0 "x" "x" #'ignore 0)
            (should (= (length scheduled) 1))
            (should (equal (nth 0 (car scheduled)) 0.05))
            (should (equal (car (last (car scheduled))) 1))
            ;; Capped: a wedged exit function cannot re-arm forever.
            (ebp-sync--run-exit-fn buf 0 "x" "x" #'ignore 20)
            (should (= (length scheduled) 1))))
      (kill-buffer buf))))

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
