;;; ebp-sync-test.el --- ERT for the Section 19 buffer bridge -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; Headless: the deferred track-changes signal rides timers that batch
;; Emacs never runs, so tests drive `ebp-sync-flush' directly — the same
;; entry point the signal closure calls.  Outbound frames are captured by
;; stubbing `ebp-client--request'; a captured callback is invoked by hand
;; to play the Companion's answer.

(require 'ert)
(require 'ebp)
(require 'ebp-sync)
;; Loaded HERE so the R1 eglot tests' `cl-letf' stubs land on top of the
;; real definitions — `ebp-sync--ensure-eglot's own soft (require 'eglot)
;; would otherwise load the file mid-test and overwrite the stubs.
(require 'eglot)

(defmacro ebp-sync-test--with (seed &rest body)
  "One attached buffer mirroring SEED, with `sent' capturing requests.
Each element of `sent' is (METHOD PARAMS CALLBACK), newest first."
  (declare (indent 1))
  `(let* ((sent nil)
          (client (ebp-client-create
                   :receipt-file (make-temp-file "ebp-sync-test"))))
     (cl-letf (((symbol-function 'ebp-client--request)
                (lambda (_c method params cb &optional _t)
                  (push (list method params cb) sent))))
       (ebp-client--handle-edit-open
        client (list :document "doc:1" :editor_id "body"
                     :session (make-string 32 ?a) :seq 0
                     :text ,seed :cursor 0))
       (with-temp-buffer
         (ebp-sync-attach client "doc:1" "body")
         (ignore sent)
         ,@body))))

(ert-deftest ebp-sync-attach-adopts-mirror-text ()
  "Attach seeds the buffer from the live mirror without echoing it."
  (ebp-sync-test--with "seed text"
    (should (equal (buffer-string) "seed text"))
    (ebp-sync-flush)
    (should-not sent)))

(ert-deftest ebp-sync-local-edit-becomes-one-apply ()
  "A buffer edit flushes as one edit.apply with scalar arithmetic."
  (ebp-sync-test--with "hello world"
    (goto-char 6)
    (insert "!")
    (ebp-sync-flush)
    (should (= 1 (length sent)))
    (pcase-let ((`(,method ,params ,_cb) (car sent)))
      (should (eq method 'edit.apply))
      (should (= (plist-get params :start) 5))
      (should (= (plist-get params :del) 0))
      (should (equal (plist-get params :text) "!"))
      (should (= (plist-get params :len) 12))
      (should (= (plist-get params :seq) 1)))))

(ert-deftest ebp-sync-astral-edit-counts-scalars ()
  "An astral-plane insertion carries scalar counts (chars, not UTF-16)."
  (ebp-sync-test--with "ab"
    (goto-char 2)
    (insert "😀")
    (ebp-sync-flush)
    (pcase-let ((`(,_m ,params ,_cb) (car sent)))
      (should (= (plist-get params :start) 1))
      (should (equal (plist-get params :text) "😀"))
      ;; a + emoji + b = 3 scalar values.
      (should (= (plist-get params :len) 3)))))

(ert-deftest ebp-sync-applied-result-advances-and-drains ()
  "An applied result adopts into the mirror and pumps the next splice."
  (ebp-sync-test--with "abc"
    (goto-char (point-max))
    (insert "d")
    (ebp-sync-flush)
    (pcase-let ((`(,_m ,_p ,cb) (car sent)))
      (funcall cb '(:status "applied" :seq 1) nil))
    (should (equal (ebp-client-editor-text client "doc:1" "body") "abcd"))
    ;; The next edit reuses the advanced seq.
    (goto-char (point-max))
    (insert "e")
    (ebp-sync-flush)
    (pcase-let ((`(,_m ,params ,_cb) (car sent)))
      (should (= (plist-get params :seq) 2))
      (should (= (plist-get params :len) 5)))))

(ert-deftest ebp-sync-inbound-splice-lands-in-buffer ()
  "An accepted edit.delta splices the buffer, preserves point, echoes nothing."
  (ebp-sync-test--with "hello world"
    (goto-char (point-max))                 ; point after the splice region
    (ebp-client--handle-edit-delta
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?a) :seq 1
                  :start 0 :del 5 :text "goodbye" :len 13))
    (should (equal (buffer-string) "goodbye world"))
    (should (= (point) (point-max)))        ; adjusted, still at end
    (ebp-sync-flush)
    (should-not (cl-find 'edit.apply sent :key #'car))))

(ert-deftest ebp-sync-refused-apply-resyncs-once ()
  "A stale/refused apply drops pending state and requests edit.resync."
  (ebp-sync-test--with "abc"
    (goto-char (point-max))
    (insert "d")
    (ebp-sync-flush)
    (pcase-let ((`(,_m ,_p ,cb) (car sent)))
      (funcall cb "stale" nil))
    (should (cl-find 'edit.resync sent :key #'car))
    (should-not ebp-sync--queue)
    (should-not ebp-sync--inflight)))

(ert-deftest ebp-sync-race-drops-local-and-resyncs ()
  "A remote splice racing an unflushed local edit never guesses:
local pending state drops and one resync goes out."
  (ebp-sync-test--with "hello"
    (goto-char (point-max))
    (insert "X")                            ; unflushed local edit
    (ebp-client--handle-edit-delta
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?a) :seq 1
                  :start 0 :del 1 :text "J" :len 5))
    (should (cl-find 'edit.resync sent :key #'car))
    (should-not (cl-find 'edit.apply sent :key #'car))))

(ert-deftest ebp-sync-reseed-adopts-and-does-not-echo ()
  "A fresh edit.open (post-resync) replaces the buffer silently."
  (ebp-sync-test--with "old text"
    (ebp-client--handle-edit-open
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?b) :seq 0
                  :text "fresh text" :cursor 0))
    (should (equal (buffer-string) "fresh text"))
    (ebp-sync-flush)
    (should-not (cl-find 'edit.apply sent :key #'car))))

(ert-deftest ebp-sync-reseed-identical-leaves-buffer-unmodified ()
  "An equal seed is not re-inserted: a clean file buffer stays clean."
  (ebp-sync-test--with "same text"
    (set-buffer-modified-p nil)
    (ebp-client--handle-edit-open
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?b) :seq 0
                  :text "same text" :cursor 0))
    (should (equal (buffer-string) "same text"))
    (should-not (buffer-modified-p))))

(ert-deftest ebp-sync-reseed-refuses-a-write-protected-buffer ()
  "SPEC 19.3: write protection is not overridden by the reseed.  The
buffer keeps its text and answers with the restoring edit.apply."
  (ebp-sync-test--with "mine"
    (setq buffer-read-only t)
    (ebp-client--handle-edit-open
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?b) :seq 0
                  :text "theirs" :cursor 0))
    (should (equal (buffer-string) "mine"))
    (let ((applies (cl-remove-if-not (lambda (s) (eq (car s) 'edit.apply))
                                     sent)))
      (should (= 1 (length applies)))
      (pcase-let ((`(,_m ,params ,_cb) (car applies)))
        (should (= (plist-get params :start) 0))
        (should (= (plist-get params :del) 6))   ; the whole seed
        (should (equal (plist-get params :text) "mine"))
        (should (= (plist-get params :seq) 1))))))

(ert-deftest ebp-sync-attach-over-an-agreeing-buffer-leaves-it-unmodified ()
  "The reseed's equality guard, on the OTHER adoption path.  Attach over
a mirror that already holds the buffer's text must not re-insert it: a
reconnect, or a second open of an editor whose session is still live,
otherwise marks a clean file buffer modified with byte-identical text —
and the flag then outlives the save that had just cleared it.  A
DIFFERENT seed still adopts; the guard skips a no-op, it does not
disable attach."
  (ebp-sync-test--with "same text"
    (set-buffer-modified-p nil)
    (ebp-sync-attach client "doc:1" "body")
    (should (equal (buffer-string) "same text"))
    (should-not (buffer-modified-p))
    (ebp-client--handle-edit-open
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?b) :seq 0
                  :text "other text" :cursor 0))
    (ebp-sync-attach client "doc:1" "body")
    (should (equal (buffer-string) "other text"))))

(ert-deftest ebp-sync-second-attach-on-a-key-detaches-the-first ()
  "One buffer per (client, document, editor-id): the previous holder is
released by KEY, so no orphan tracker keeps sending for a session the
routing table no longer points at."
  (ebp-sync-test--with "text"
    (let ((first (current-buffer)))
      (with-temp-buffer
        (let ((second (current-buffer)))
          (ebp-sync-attach client "doc:1" "body")
          (should (eq (ebp-sync-buffer client "doc:1" "body") second))
          (with-current-buffer first
            (should-not ebp-sync--tracker)
            (should-not ebp-sync--client)))))))

(ert-deftest ebp-sync-close-detaches ()
  "edit.close releases the buffer binding and its tracker."
  (ebp-sync-test--with "text"
    (ebp-client--handle-edit-close
     client (list :document "doc:1" :editor_id "body"))
    (should-not ebp-sync--tracker)
    (should-not ebp-sync--client)))

(ert-deftest ebp-sync-detach-is-idempotent ()
  "Detach twice, then edit freely: nothing is sent, nothing errors."
  (ebp-sync-test--with "text"
    (ebp-sync-detach)
    (ebp-sync-detach)
    (insert "more")
    (should-not sent)))

(ert-deftest ebp-sync-diagnostics-shape-dedupe-and-seq-restamp ()
  "SPEC 19.5: the push carries 0-based scalar offsets under the live
session/seq; unchanged content is not re-sent, but a seq advance
re-sends identical content (the Companion discarded the old seq's)."
  (ebp-sync-test--with "text"
    (let ((notified nil))
      (cl-letf (((symbol-function 'ebp-client-notify)
                 (lambda (_c method params)
                   (push (cons method params) notified)))
                ((symbol-function 'flymake-diagnostics)
                 (lambda (&rest _)
                   (list (flymake-make-diagnostic
                          (current-buffer) 1 5 :warning "Spelling")))))
        (ebp-sync--push-diagnostics (current-buffer))
        (should (= 1 (length notified)))
        (pcase-let ((`(,method . ,params) (car notified)))
          (should (eq method 'diagnostics.show))
          (should (equal (plist-get params :editor_id) "body"))
          (should (= (plist-get params :seq) 0))
          (let ((d (aref (plist-get params :diagnostics) 0)))
            (should (= (plist-get d :start) 0))
            (should (= (plist-get d :end) 4))
            (should (equal (plist-get d :severity) "warning"))
            (should (equal (plist-get d :message) "Spelling"))))
        ;; Same content, same seq: deduped.
        (ebp-sync--push-diagnostics (current-buffer))
        (should (= 1 (length notified)))
        ;; Same content, advanced seq: goes out again.
        (let ((ed (gethash (cons "doc:1" "body")
                           (ebp-client-editors client))))
          (setf (plist-get ed :seq) 1))
        (ebp-sync--push-diagnostics (current-buffer))
        (should (= 2 (length notified)))
        (should (= (plist-get (cdar notified) :seq) 1))))))

(ert-deftest ebp-sync-severity-mapping ()
  "Flymake note becomes SPEC 19.5 `info' — `note' is not a wire severity."
  (should (equal (ebp-sync--severity :error) "error"))
  (should (equal (ebp-sync--severity :warning) "warning"))
  (should (equal (ebp-sync--severity :note) "info")))

(ert-deftest ebp-sync-face-role-resolution ()
  "Direct hits, list normalization, :inherit chains, unknown -> nil."
  (should (equal (ebp-sync--face-role 'font-lock-keyword-face) "keyword"))
  (should (equal (ebp-sync--face-role '(font-lock-string-face bold)) "string"))
  (make-face 'ebp-sync-test--derived)
  (set-face-attribute 'ebp-sync-test--derived nil
                      :inherit 'font-lock-keyword-face)
  (should (equal (ebp-sync--face-role 'ebp-sync-test--derived) "keyword"))
  (should-not (ebp-sync--face-role nil))
  (should-not (ebp-sync--face-role 'bold)))

(ert-deftest ebp-sync-fontify-runs-are-sorted-roles ()
  "Real font-lock output: sorted, non-overlapping, contract roles only."
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(defun foo ())\n;; a comment\n\"a string\"\n")
    (let ((runs (ebp-sync--fontify-runs))
          (allowed '("comment" "string" "keyword" "function" "constant"
                     "variable" "type" "number" "operator" "preprocessor"
                     "heading" "link" "todo" "done" "tag"))
          (last-end -1))
      (should runs)
      (dolist (r runs)
        (should (member (plist-get r :role) allowed))
        (should (>= (plist-get r :start) last-end))
        (should (> (plist-get r :end) (plist-get r :start)))
        (setq last-end (plist-get r :end)))
      (should (cl-find "keyword" runs
                       :key (lambda (r) (plist-get r :role)) :test #'equal))
      (should (cl-find "comment" runs
                       :key (lambda (r) (plist-get r :role)) :test #'equal)))))

(ert-deftest ebp-sync-fontify-push-dedupe-and-cap ()
  "Seq-stamped dedupe like diagnostics; oversized buffers push nothing."
  (ebp-sync-test--with "(defun foo ())"
    (let ((notified nil))
      (cl-letf (((symbol-function 'ebp-client-notify)
                 (lambda (_c method params)
                   (push (cons method params) notified)))
                ((symbol-function 'ebp-sync--fontify-runs)
                 (lambda () (list (list :start 1 :end 6 :role "keyword")))))
        (ebp-sync--push-fontify (current-buffer))
        (should (= 1 (length notified)))
        (pcase-let ((`(,method . ,params) (car notified)))
          (should (eq method 'fontify.show))
          (should (= (plist-get params :seq) 0))
          (let ((r (aref (plist-get params :runs) 0)))
            (should (= (plist-get r :start) 1))
            (should (equal (plist-get r :role) "keyword"))))
        ;; Unchanged: deduped.  Seq advance: re-sent.
        (ebp-sync--push-fontify (current-buffer))
        (should (= 1 (length notified)))
        (let ((ed (gethash (cons "doc:1" "body")
                           (ebp-client-editors client))))
          (setf (plist-get ed :seq) 1))
        (ebp-sync--push-fontify (current-buffer))
        (should (= 2 (length notified)))
        ;; Over the size cap nothing goes out, even with changes.
        (let ((ebp-sync-fontify-max-chars 3))
          (setf (plist-get (gethash (cons "doc:1" "body")
                                    (ebp-client-editors client))
                           :seq)
                2)
          (ebp-sync--push-fontify (current-buffer))
          (should (= 2 (length notified))))))))

(ert-deftest ebp-sync-eldoc-push-shape-dedupe-and-seq-restamp ()
  "SPEC 19.5: eldoc.show carries {editor_id, session, seq, text} and NO
document; unchanged text is not re-sent, a seq advance re-sends it."
  (ebp-sync-test--with "text"
    (let ((notified nil))
      (cl-letf (((symbol-function 'ebp-client-notify)
                 (lambda (_c method params)
                   (push (cons method params) notified))))
        (ebp-sync--push-eldoc (current-buffer) "foo: (foo ARG)")
        (should (= 1 (length notified)))
        (pcase-let ((`(,method . ,params) (car notified)))
          (should (eq method 'eldoc.show))
          (should (equal (plist-get params :editor_id) "body"))
          (should (= (plist-get params :seq) 0))
          (should (equal (plist-get params :text) "foo: (foo ARG)"))
          (should-not (plist-member params :document)))
        ;; Same text, same seq: deduped.
        (ebp-sync--push-eldoc (current-buffer) "foo: (foo ARG)")
        (should (= 1 (length notified)))
        ;; Same text, advanced seq: goes out again.
        (let ((ed (gethash (cons "doc:1" "body")
                           (ebp-client-editors client))))
          (setf (plist-get ed :seq) 1))
        (ebp-sync--push-eldoc (current-buffer) "foo: (foo ARG)")
        (should (= 2 (length notified)))
        (should (= (plist-get (cdar notified) :seq) 1))))))

(ert-deftest ebp-sync-eldoc-clears-on-empty ()
  "Leaving a symbol is a transition, not a no-op: nil pushes the empty
string so the phone's doc line blanks.  A second nil is deduped."
  (ebp-sync-test--with "text"
    (let ((notified nil))
      (cl-letf (((symbol-function 'ebp-client-notify)
                 (lambda (_c method params)
                   (push (cons method params) notified))))
        (ebp-sync--push-eldoc (current-buffer) "foo: (foo ARG)")
        (ebp-sync--push-eldoc (current-buffer) nil)
        (should (= 2 (length notified)))
        (should (equal (plist-get (cdar notified) :text) ""))
        (ebp-sync--push-eldoc (current-buffer) nil)
        (should (= 2 (length notified)))))))

(ert-deftest ebp-sync-eldoc-runs-every-backend-and-formats ()
  "Sync returns and async callbacks both collect; each doc contributes
its FIRST line, `:thing' prefixes it, and the join is backend order."
  (ebp-sync-test--with "text"
    (let ((notified nil)
          (eldoc-documentation-functions
           (list (lambda (_cb) "car: (car LIST)\nsecond line")
                 (lambda (cb) (funcall cb "the sig" :thing "cdr") t))))
      (cl-letf (((symbol-function 'ebp-client-notify)
                 (lambda (_c method params)
                   (push (cons method params) notified))))
        (ebp-sync--run-eldoc (current-buffer))
        (should notified)
        (should (equal (plist-get (cdar notified) :text)
                       "car: (car LIST)  •  cdr: the sig"))))))

(ert-deftest ebp-sync-eldoc-caret-gates-on-selection-and-toggle ()
  "A selection drag is not a request for documentation, and the toggle
switches the rider off entirely.  A collapsed caret moves point without
leaving it moved."
  (ebp-sync-test--with "(car x)"
    (let* ((notified nil)
           (seen nil)
           (eldoc-documentation-functions
            (list (lambda (_cb) (setq seen (point)) "doc"))))
      (cl-letf (((symbol-function 'ebp-client-notify)
                 (lambda (_c method params)
                   (push (cons method params) notified))))
        (goto-char (point-min))
        ;; A non-collapsed caret pushes nothing.
        (ebp-sync--on-caret client "doc:1" "body" 2 1 4)
        (should-not notified)
        ;; The toggle off pushes nothing.
        (let ((ebp-sync-eldoc nil))
          (ebp-sync--on-caret client "doc:1" "body" 2 nil nil))
        (should-not notified)
        ;; A collapsed caret runs the backends at cursor+1 and restores.
        (ebp-sync--on-caret client "doc:1" "body" 2 nil nil)
        (should (= 1 (length notified)))
        (should (= seen 3))
        (should (= (point) (point-min)))))))

(ert-deftest ebp-sync-eldoc-format-caps-at-200-columns ()
  "The line is bounded for the strip it renders into."
  (let ((long (make-string 400 ?x)))
    (should (= 200 (string-width (ebp-sync--format-docs
                                  (list (cons long nil))))))
    (should-not (ebp-sync--format-docs nil))))

;;;; Narrowing: the §19 mirror is the DOCUMENT, never the visible part

;; The module header has always said "Synced buffers must not be
;; narrowed" and nothing enforced it.  These pin the enforcement: every
;; operation runs WIDENED, wire offsets stay absolute (origin 1), and a
;; restriction that CAN survive is restored.  A restriction that cannot
;; — the full-document adopt deletes the very text its markers are
;; anchored in — is documented rather than faked.

(defconst ebp-sync-test--doc "AAA\nBBB\nCCC\n"
  "Twelve chars; positions 5..8 are the middle line, \"BBB\\n\".")

(defun ebp-sync-test--whole ()
  "The whole buffer regardless of the restriction in force."
  (save-restriction (widen) (buffer-string)))

(ert-deftest ebp-sync-attach-compares-the-whole-document ()
  "Attach's equality guard reads the DOCUMENT, not the visible region.
Unwidened it compared \"BBB\\n\" against a mirror holding the whole file,
called that a difference, and adopted — and the adopt path replaces the
WHOLE buffer, so a re-attach over a narrowed buffer marked it modified
and dropped the user's restriction for a seed it already held."
  (ebp-sync-test--with ebp-sync-test--doc
    (set-buffer-modified-p nil)
    (narrow-to-region 5 9)
    (should (equal (buffer-string) "BBB\n"))
    (ebp-sync-attach client "doc:1" "body")
    (should (equal (ebp-sync-test--whole) ebp-sync-test--doc))
    (should-not (buffer-modified-p))
    ;; The restriction is the user's and nothing here replaced any text.
    (should (buffer-narrowed-p))
    (should (equal (buffer-string) "BBB\n"))))

(ert-deftest ebp-sync-inbound-splice-lands-at-an-absolute-position ()
  "A delta whose target lies OUTSIDE the restriction still lands.
`delete-region' validates against the accessible portion, so an
unwidened splice signalled `args-out-of-range' and degraded to
`edit.resync' — for every keystroke the phone made outside the region.
The mirror had already advanced, so the two diverged and the resync's
reseed could not repair it."
  (ebp-sync-test--with ebp-sync-test--doc
    (narrow-to-region 5 9)
    (ebp-client--handle-edit-delta
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?a) :seq 1
                  :start 0 :del 3 :text "ZZZ" :len 12))
    (should (equal (ebp-sync-test--whole) "ZZZ\nBBB\nCCC\n"))
    (should-not (cl-find 'edit.resync sent :key #'car))
    ;; Mirror and buffer agree — the whole point of the coordinate system.
    (should (equal (ebp-client-editor-text client "doc:1" "body")
                   (ebp-sync-test--whole)))))

(ert-deftest ebp-sync-splice-restores-the-restriction-and-point ()
  "A splice the user cannot see does not disturb what they can.
`save-restriction' restores through markers, so a splice BEFORE the
region leaves the same characters visible; `save-excursion' keeps point
on the same character.  Text motion moves both — that is correct, and
the assertion is on the CHARACTERS, not the numbers."
  (ebp-sync-test--with ebp-sync-test--doc
    (narrow-to-region 5 9)
    (goto-char 6)                       ; the middle B
    (ebp-client--handle-edit-delta
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?a) :seq 1
                  :start 0 :del 3 :text "Z" :len 10))
    (should (equal (ebp-sync-test--whole) "Z\nBBB\nCCC\n"))
    (should (buffer-narrowed-p))
    (should (equal (buffer-string) "BBB\n"))
    ;; Same character, two positions earlier: bounds and point tracked
    ;; the two characters the splice removed ahead of them.
    (should (= (point) 4))
    (should (= (char-after) ?B))))

(ert-deftest ebp-sync-narrowed-session-survives-a-delta-outside-it ()
  "The tracker constraint, which no arithmetic fix reaches.
`track-changes' asserts `(<= (point-min) beg end (point-max))' UNWIDENED
around its own bookkeeping, and its state is created with the ACCESSIBLE
bounds in force at registration.  So the register must run widened (or
the first out-of-region change signals `cl-assertion-failed' however
carefully the splice itself widens), and every fetch must run widened
(or our OWN widened splice poisons the shared state).  Both are proven
here, in that order, because only the FIRST change after a registration
reaches the register: a fetch that reports a change re-creates the state
with the bounds then in force, and a fetch with nothing pending does
not (measured)."
  (ebp-sync-test--with ebp-sync-test--doc
    (set-buffer-modified-p nil)
    (narrow-to-region 5 9)
    (ebp-sync-attach client "doc:1" "body")   ; registers under the narrowing
    (should (buffer-narrowed-p))
    ;; PHASE 1 — the REGISTER pin.  The very first change is outside the
    ;; restriction, and nothing has re-created the tracker state.
    (ebp-client--handle-edit-delta
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?a) :seq 1
                  :start 0 :del 3 :text "Q" :len 10))
    (should (equal (ebp-sync-test--whole) "Q\nBBB\nCCC\n"))
    (should-not (cl-find 'edit.resync sent :key #'car))
    (should (buffer-narrowed-p))
    (should (equal (buffer-string) "BBB\n"))
    ;; PHASE 2 — the FETCH pins.  A local edit inside the region, sent
    ;; and applied, then another delta outside it.
    (goto-char 4)
    (insert "Z")
    (ebp-sync-flush)
    (pcase-let ((`(,_m ,_p ,cb) (car sent)))
      (funcall cb '(:status "applied" :seq 2) nil))
    (should (equal (ebp-client-editor-text client "doc:1" "body")
                   "Q\nBZBB\nCCC\n"))
    (ebp-client--handle-edit-delta
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?a) :seq 3
                  :start 0 :del 1 :text "XY" :len 12))
    (should (equal (ebp-sync-test--whole) "XY\nBZBB\nCCC\n"))
    (should-not (cl-find 'edit.resync sent :key #'car))
    (should (buffer-narrowed-p))
    ;; And the tracker is still usable afterwards.
    (goto-char (point-max))
    (insert "!")
    (ebp-sync-flush)
    (should (cl-find 'edit.apply sent :key #'car))))

(ert-deftest ebp-sync-a-foreign-edit-outside-the-region-does-not-escape ()
  "A package editing outside the user's restriction is ordinary Emacs —
org, a formatter, `whitespace-cleanup' all do it under their own widen.
The pending-change fetch that opens `ebp-sync--on-splice' sits OUTSIDE
that function's `condition-case', so unwidened it did not degrade to a
resync: `cl-assertion-failed' escaped into ebp.el's notification
dispatch and took the rest of the hook fan-out with it.  The race is
real and its answer is one resync; the signal was never part of it."
  (ebp-sync-test--with ebp-sync-test--doc
    (narrow-to-region 5 9)
    (save-restriction (widen) (goto-char 1) (insert "Z"))
    (ebp-client--handle-edit-delta
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?a) :seq 1
                  :start 0 :del 1 :text "!" :len 12))
    (should (cl-find 'edit.resync sent :key #'car))))

(ert-deftest ebp-sync-local-edit-reports-whole-document-offsets ()
  "CHARACTERIZATION, green before and after: the outbound leg is already
the coordinate system of record.  `track-changes' reports ABSOLUTE
buffer positions, so `(1- beg)' is a document offset under any
restriction.  Pinned so a later \"fix\" toward region-relative offsets
goes red instead of silently re-opening the whole defect."
  (ebp-sync-test--with ebp-sync-test--doc
    (narrow-to-region 5 9)
    (goto-char 6)
    (insert "Z")
    (ebp-sync-flush)
    (pcase-let ((`(,method ,params ,_cb) (car sent)))
      (should (eq method 'edit.apply))
      (should (= (plist-get params :start) 5))
      (should (= (plist-get params :del) 0))
      (should (equal (plist-get params :text) "Z"))
      (should (= (plist-get params :len) 13)))))

(ert-deftest ebp-sync-reseed-replaces-the-whole-document ()
  "The reseed adopts over the DOCUMENT.  Unwidened, `delete-region'
between `(point-min)' and `(point-max)' emptied only the visible region
and the insert refilled it — so the Companion's whole document was
spliced INTO the narrow region and the invisible prefix and suffix
survived around it.  The restriction cannot come back: its markers were
anchored in the text this replaced, so the buffer is left WIDE, which is
the honest outcome rather than an arbitrary window into foreign text."
  (ebp-sync-test--with ebp-sync-test--doc
    (narrow-to-region 5 9)
    (ebp-client--handle-edit-open
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?b) :seq 0
                  :text "WHOLE\nNEW\n" :cursor 0))
    (should (equal (ebp-sync-test--whole) "WHOLE\nNEW\n"))
    (should-not (buffer-narrowed-p))))

(ert-deftest ebp-sync-write-protected-reseed-restores-the-whole-document ()
  "The refusing leg answers with the DOCUMENT, not the visible region.
SPEC 19.3 has the write-protected endpoint restore its own authoritative
text at the fresh seq.  Unwidened it sent the accessible portion as
`0 (length seed) mine' — a whole-document replacement built from a
fragment, which truncates the DEVICE's document to whatever the user
happened to be narrowed to."
  (ebp-sync-test--with ebp-sync-test--doc
    (narrow-to-region 5 9)
    (setq buffer-read-only t)
    (ebp-client--handle-edit-open
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?b) :seq 0
                  :text "theirs" :cursor 0))
    (should (equal (ebp-sync-test--whole) ebp-sync-test--doc))
    (let ((applies (cl-remove-if-not (lambda (s) (eq (car s) 'edit.apply))
                                     sent)))
      (should (= 1 (length applies)))
      (pcase-let ((`(,_m ,params ,_cb) (car applies)))
        (should (= (plist-get params :start) 0))
        (should (= (plist-get params :del) 6))
        (should (equal (plist-get params :text) ebp-sync-test--doc))))))

(ert-deftest ebp-sync-caret-answers-at-the-absolute-position ()
  "The one site that misplaces SILENTLY.  `goto-char' clamps to BOTH
accessible bounds without signalling, so every caret the phone reported
below the restriction collapsed onto `point-min' and eldoc answered
confidently about the wrong symbol."
  (ebp-sync-test--with ebp-sync-test--doc
    (let* ((seen nil)
           (eldoc-documentation-functions
            (list (lambda (_cb) (push (point) seen) "doc"))))
      (cl-letf (((symbol-function 'ebp-client-notify) #'ignore))
        (narrow-to-region 5 9)
        (ebp-sync--on-caret client "doc:1" "body" 0 nil nil)     ; -> 1
        (ebp-sync--on-caret client "doc:1" "body" 11 nil nil)    ; -> 12
        (should (equal (nreverse seen) '(1 12)))
        ;; Point and the restriction are the user's, both restored.
        (should (buffer-narrowed-p))
        (should (equal (buffer-string) "BBB\n"))))))

(ert-deftest ebp-sync-fontify-runs-cover-the-whole-document ()
  "The fontify rider walks the DOCUMENT.  Its offsets were always
absolute, so nothing was ever misplaced — but `font-lock-ensure' and the
walk were both bounded by the restriction, so the phone lost every
highlight outside the visible region while showing the whole file."
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert ";; head\n(defun f ())\n;; tail\n")
    (narrow-to-region 9 22)             ; just the defun line
    (let ((runs (ebp-sync--fontify-runs)))
      ;; The leading comment is at buffer 1..8 = wire offset 0.
      (should (cl-find-if (lambda (r) (and (= (plist-get r :start) 0)
                                           (equal (plist-get r :role)
                                                  "comment")))
                          runs))
      ;; ...and the trailing one at buffer 22.. = wire offset 21.
      (should (cl-find-if (lambda (r) (and (= (plist-get r :start) 21)
                                           (equal (plist-get r :role)
                                                  "comment")))
                          runs))
      ;; The user's restriction is untouched by a read-only walk.
      (should (buffer-narrowed-p)))))

(ert-deftest ebp-sync-attached-buffer-clientless-lookup ()
  "`ebp-sync-attached-buffer' resolves (DOCUMENT . EDITOR-ID) with no
client in hand — the form `ebp-complete's R0 live arm needs, sound
under the single-client floor — and never returns a dead buffer."
  (let ((live (generate-new-buffer " *ebp-sync-test live*"))
        (dead (generate-new-buffer " *ebp-sync-test dead*"))
        (k1 (list 'client-a "doc:acc" "body"))
        (k2 (list 'client-a "doc:dead" "body")))
    (unwind-protect
        (progn
          (puthash k1 live ebp-sync--table)
          (puthash k2 dead ebp-sync--table)
          (kill-buffer dead)
          (should (eq (ebp-sync-attached-buffer "doc:acc" "body") live))
          (should-not (ebp-sync-attached-buffer "doc:dead" "body"))
          (should-not (ebp-sync-attached-buffer "doc:acc" "other")))
      (remhash k1 ebp-sync--table)
      (remhash k2 ebp-sync--table)
      (when (buffer-live-p live) (kill-buffer live)))))

;;;; R1: the language tooling arm (PLAN-glasspane-completion.md)

(defmacro ebp-sync-test--with-file-buffer (name content &rest body)
  "Run BODY in a buffer visiting a temp file NAME-*.CONTENT, attached.
Binds `client', `buf', and `file'.  The mirror seed equals CONTENT so
attach never adopts.  Diagnostics are off — these tests exercise the
tooling arm, not the rider."
  (declare (indent 2))
  `(let* ((file (make-temp-file ,name nil
                                (if (string-suffix-p ".el" ,name) ".el" ".py")
                                ,content))
          (client (ebp-client-create
                   :receipt-file (make-temp-file "ebp-r1")))
          (ebp-sync-diagnostics nil)
          (buf (let ((enable-local-variables nil))
                 (find-file-noselect file))))
     (unwind-protect
         (with-current-buffer buf
           (puthash (cons "doc:r1" "body")
                    (list :session "S" :seq 0 :text ,content :cursor 0)
                    (ebp-client-editors client))
           ,@body)
       (with-current-buffer buf
         (ebp-sync-detach)
         (set-buffer-modified-p nil))
       (kill-buffer buf)
       (delete-file file))))

(ert-deftest ebp-sync-eglot-connects-directly-and-throttles ()
  "Attach connects eglot DIRECTLY (never `eglot-ensure', whose connect
waits on a `post-command-hook' that never fires headless), asynchronously
\(`eglot-sync-connect' nil), at most once per 30s PER PROJECT — a second
file of the same project inside a cold server's async-init window must
not spawn a second server (the R1 review's headline: the server reaches
`eglot-current-server' only after the initialize handshake, so during
startup every project buffer passes the no-server gate).  A reopen past
the window reconnects — the reaped-server path."
  (ebp-sync-test--with-file-buffer "ebp-r1-eglot" "x = 1\n"
    (clrhash ebp-sync--eglot-attempts)
    (should (eq major-mode 'python-mode))
    (let ((connects nil) (sync-seen 'unset))
      (cl-letf (((symbol-function 'eglot-current-server) (lambda () nil))
                ((symbol-function 'eglot--guess-contact)
                 (lambda (&optional _) '(modes proj class contact ids)))
                ((symbol-function 'eglot--connect)
                 (lambda (&rest args)
                   (setq sync-seen eglot-sync-connect)
                   (push args connects))))
        (ebp-sync-attach client "doc:r1" "body" buf)
        (should (equal connects '((modes proj class contact ids))))
        (should (eq sync-seen nil))
        ;; Same open window, same buffer: throttled.
        (ebp-sync-attach client "doc:r1" "body" buf)
        (should (= (length connects) 1))
        ;; Same open window, DIFFERENT buffer of the same project:
        ;; still throttled — the stamp is project-keyed, not
        ;; buffer-local.
        (let* ((file2 (make-temp-file "ebp-r1-eglot-b" nil ".py" "y = 2\n"))
               (buf2 (let ((enable-local-variables nil))
                       (find-file-noselect file2))))
          (unwind-protect
              (with-current-buffer buf2
                (puthash (cons "doc:r1b" "body")
                         (list :session "S" :seq 0 :text "y = 2\n" :cursor 0)
                         (ebp-client-editors client))
                (ebp-sync-attach client "doc:r1b" "body" buf2)
                (should (= (length connects) 1)))
            (with-current-buffer buf2
              (ebp-sync-detach)
              (set-buffer-modified-p nil))
            (kill-buffer buf2)
            (delete-file file2)))
        ;; Past the window: reconnect (revives an OS-reaped server).
        (with-current-buffer buf
          (puthash (ebp-sync--eglot-project-key) (- (float-time) 31)
                   ebp-sync--eglot-attempts)
          (ebp-sync-attach client "doc:r1" "body" buf)
          (should (= (length connects) 2)))))))

(ert-deftest ebp-sync-eglot-gate-refuses ()
  "No connect for: a mode outside `ebp-sync-eglot-modes', the feature
off, or a server already running."
  (ebp-sync-test--with-file-buffer "ebp-r1-gate" "x = 1\n"
    (clrhash ebp-sync--eglot-attempts)
    (let ((connects nil))
      (cl-letf (((symbol-function 'eglot-current-server) (lambda () nil))
                ((symbol-function 'eglot--guess-contact)
                 (lambda (&optional _) '(a b c d e)))
                ((symbol-function 'eglot--connect)
                 (lambda (&rest args) (push args connects))))
        (let ((ebp-sync-eglot nil))
          (ebp-sync-attach client "doc:r1" "body" buf))
        (should-not connects)
        (fundamental-mode)
        (clrhash ebp-sync--eglot-attempts)
        (ebp-sync-attach client "doc:r1" "body" buf)
        (should-not connects)
        (python-mode)
        (clrhash ebp-sync--eglot-attempts)
        (cl-letf (((symbol-function 'eglot-current-server)
                   (lambda () 'live-server)))
          (ebp-sync-attach client "doc:r1" "body" buf))
        (should-not connects)))))

(ert-deftest ebp-sync-elisp-backend-swap-and-restore ()
  "Attach swaps `elisp-flymake-byte-compile' (spawns \"emacs -batch\" —
impossible on Android, a subprocess per pause everywhere) for the
in-process backend; detach restores stock.  checkdoc is untouched."
  (ebp-sync-test--with-file-buffer "ebp-r1-swap.el" "(setq x 1)\n"
    (should (eq major-mode 'emacs-lisp-mode))
    (should (memq #'elisp-flymake-byte-compile flymake-diagnostic-functions))
    ;; Platform-gated OFF (the desktop default): stock backend stays —
    ;; its subprocess isolation is the safer trade wherever spawning
    ;; works.
    (let ((ebp-sync-elisp-inprocess nil))
      (ebp-sync-attach client "doc:r1" "body" buf))
    (should (memq #'elisp-flymake-byte-compile flymake-diagnostic-functions))
    (should-not (memq #'ebp-sync--flymake-elisp flymake-diagnostic-functions))
    (ebp-sync-detach)
    ;; Gated ON (the Android default): swapped at attach, restored at
    ;; detach.
    (let ((ebp-sync-elisp-inprocess t))
      (ebp-sync-attach client "doc:r1" "body" buf))
    (should-not (memq #'elisp-flymake-byte-compile
                      flymake-diagnostic-functions))
    (should (memq #'ebp-sync--flymake-elisp flymake-diagnostic-functions))
    (should (memq #'elisp-flymake-checkdoc flymake-diagnostic-functions))
    (ebp-sync-detach)
    (should (memq #'elisp-flymake-byte-compile flymake-diagnostic-functions))
    (should-not (memq #'ebp-sync--flymake-elisp
                      flymake-diagnostic-functions))))

(ert-deftest ebp-sync-flymake-elisp-parens-and-warnings ()
  "The in-process backend: unbalanced parens report an :error directly
and the compile's useless end-of-file duplicate is dropped; balanced
input reports real byte-compile warnings with no subprocess; an
unescaped `?(' char literal false-positives the paren pre-scan but
must NOT suppress the compile's real warnings (R1 review)."
  (let ((trusted-content :all))
    (with-temp-buffer
      (insert "(defun ebp-r1-broken (")
      (let (got)
        (ebp-sync--flymake-elisp (lambda (diags) (setq got diags)))
        (should (cl-find-if (lambda (d) (eq (flymake-diagnostic-type d)
                                            :error))
                            got))
        (should-not (cl-find-if
                     (lambda (d) (string-match-p
                                  "End of file" (flymake-diagnostic-text d)))
                     got))))
    (with-temp-buffer
      (insert ";;; -*- lexical-binding: t; -*-\n"
              "(defun ebp-r1-warns () (ebp-r1-undefined-fn-xyz))\n")
      (let (got)
        (ebp-sync--flymake-elisp (lambda (diags) (setq got diags)))
        (should (cl-find-if
                 (lambda (d)
                   (and (eq (flymake-diagnostic-type d) :warning)
                        (string-match-p "ebp-r1-undefined-fn-xyz"
                                        (flymake-diagnostic-text d))))
                 got))))
    (with-temp-buffer
      (insert ";;; -*- lexical-binding: t; -*-\n"
              "(defvar ebp-r1-char ?()\n"
              "(defun ebp-r1-lit () (ebp-r1-undefined-fn-xyz))\n")
      (let (got)
        (ebp-sync--flymake-elisp (lambda (diags) (setq got diags)))
        ;; The real warning survives the pre-scan's false positive.
        (should (cl-find-if
                 (lambda (d) (string-match-p "ebp-r1-undefined-fn-xyz"
                                             (flymake-diagnostic-text d)))
                 got))))))

(ert-deftest ebp-sync-flymake-elisp-widens ()
  "The backend reports against the DOCUMENT, not the restriction: a
narrowed attached buffer must produce no spurious paren :error, its
warnings at absolute positions, and keep its restriction — the wire
ships whole-document offsets (the module invariant; the stock backend
this swap replaces widens too)."
  (let ((trusted-content :all))
    (with-temp-buffer
      (insert ";;; -*- lexical-binding: t; -*-\n"
              "(defun ebp-r1-nrw () 1)\n"
              "(car)\n")
      (let ((car-symbol-pos (progn (goto-char (point-min))
                                   (search-forward "(car)")
                                   (1+ (match-beginning 0)))))
        ;; Narrow MID-FORM inside the defun: an unwidened scan-sexps
        ;; would signal here, and an unwidened compile would never see
        ;; the (car) outside the restriction.
        (narrow-to-region 40 50)
        (let (got)
          (ebp-sync--flymake-elisp (lambda (diags) (setq got diags)))
          (should-not (cl-find-if (lambda (d) (eq (flymake-diagnostic-type d)
                                                  :error))
                                  got))
          (let ((arity (cl-find-if
                        (lambda (d) (string-match-p
                                     "car" (flymake-diagnostic-text d)))
                        got)))
            (should arity)
            (should (= (flymake-diagnostic-beg arity) car-symbol-pos)))
          (should (buffer-narrowed-p)))))))

(ert-deftest ebp-sync-flymake-elisp-untrusted-degrades ()
  "Untrusted content (`trusted-content-p' nil — the same 30.1 gate the
stock backend applies, since macro expansion IS evaluation) skips the
compile and says so in one :note; paren errors still report."
  (with-temp-buffer                     ; no file, hence untrusted
    (insert "(car)")
    (let (got)
      (ebp-sync--flymake-elisp (lambda (diags) (setq got diags)))
      (should (= (length got) 1))
      (should (eq (flymake-diagnostic-type (car got)) :note))
      (should (string-match-p "untrusted"
                              (flymake-diagnostic-text (car got)))))))

(ert-deftest ebp-sync-flymake-elisp-repl-cookie-shifts-positions ()
  "A REPL buffer compiles under a prepended lexical-binding cookie —
the no-cookie warning can never fire against a one-expression line —
and warning positions shift back by the cookie's length."
  (with-temp-buffer
    (insert "(car)")
    (setq ebp-sync-elisp-repl t)
    (let ((trusted-content :all)
          got)
      (ebp-sync--flymake-elisp (lambda (diags) (setq got diags)))
      (should got)
      (dolist (d got)
        (should-not (string-match-p "lexical-binding"
                                    (flymake-diagnostic-text d))))
      ;; bytecomp anchors the wrong-arity warning at the offending
      ;; SYMBOL: raw position 34 in the cookie-carrying copy (32-char
      ;; cookie + "("), shifted back to buffer position 2.  A dropped
      ;; shift leaves 34, which clamps to the tiny buffer's end (6) —
      ;; the pin bites either way.
      (let ((arity (cl-find-if
                    (lambda (d) (string-match-p "car" (flymake-diagnostic-text d)))
                    got)))
        (should arity)
        (should (= (flymake-diagnostic-beg arity) 2))))))

(ert-deftest ebp-sync-settle-kicks-flymake-start ()
  "The explicit `flymake-start' kick fires from the SETTLE TIMER, never
on the jsonrpc dispatch path: neither the attach-time arm nor the
flymake enable runs a backend pass (a synchronous compile per
keystroke inside the dispatch callback was the R1 review's hot-path
finding), the settle push kicks exactly once — and a buffer whose mode
installed no backends never pays for a pass."
  (ebp-sync-test--with-file-buffer "ebp-r1-kick.el" "(setq x 1)\n"
    (let ((ebp-sync-diagnostics t)
          (ebp-sync-elisp-inprocess t)
          (kicks 0))
      (cl-letf (((symbol-function 'flymake-start)
                 (lambda (&rest _) (cl-incf kicks)))
                ((symbol-function 'ebp-client-notify)
                 (lambda (&rest _) nil)))
        (ebp-sync-attach client "doc:r1" "body" buf)
        ;; Attach armed (enable included) with ZERO backend passes.
        (should (= kicks 0))
        (ebp-sync--arm-diagnostics buf)
        (should (= kicks 0))
        ;; The settle timer's push is the sole scheduler.
        (ebp-sync--push-diagnostics buf)
        (should (= kicks 1))
        (when ebp-sync--diag-timer (cancel-timer ebp-sync--diag-timer)))))
  ;; No backends -> no pass, even at settle.
  (let* ((client (ebp-client-create :receipt-file (make-temp-file "ebp-r1k")))
         (kicks 0))
    (cl-letf (((symbol-function 'flymake-start)
               (lambda (&rest _) (cl-incf kicks)))
              ((symbol-function 'ebp-client-notify)
               (lambda (&rest _) nil)))
      (with-temp-buffer
        (puthash (cons "doc:r1k" "b")
                 (list :session "S" :seq 0 :text "" :cursor 0)
                 (ebp-client-editors client))
        (let ((ebp-sync-diagnostics t))
          (ebp-sync-attach client "doc:r1k" "b")
          (setq kicks 0)
          (ebp-sync--push-diagnostics (current-buffer))
          (should (= kicks 0))
          (when ebp-sync--diag-timer (cancel-timer ebp-sync--diag-timer))
          (ebp-sync-detach))))))

(ert-deftest ebp-sync-publish-hook-collects-soon ()
  "publishDiagnostics latency (R2): the :after method is REGISTERED on
eglot's generic — a helper-only test would pass with the method
unwired, the house lesson — and `ebp-sync--collect-soon' re-arms the
attached buffer's push at the short delay with the quiet chase reset."
  (should (cl-find-method #'eglot-handle-notification '(:after)
                          '(t (eql textDocument/publishDiagnostics))))
  (ebp-sync-test--with-file-buffer "ebp-r2-pub" "x = 1\n"
    (let ((ebp-sync-diagnostics t))
      (ebp-sync-attach client "doc:r1" "body" buf)
      ;; The URI->buffer resolver reads the ATTACH table.
      (should (eq (ebp-sync--buffer-for-path file) buf))
      (should-not (ebp-sync--buffer-for-path "/nonexistent/nope.py"))
      (when ebp-sync--diag-timer (cancel-timer ebp-sync--diag-timer))
      (setq ebp-sync--diag-timer nil ebp-sync--diag-quiet 2)
      (ebp-sync--collect-soon buf)
      (should ebp-sync--diag-timer)
      (should (= ebp-sync--diag-quiet 0))
      ;; The short latency delay, not the 3s settle.
      (should (< (- (float-time (timer--time ebp-sync--diag-timer))
                    (float-time))
                 1.0))
      (cancel-timer ebp-sync--diag-timer)
      (setq ebp-sync--diag-timer nil))))

(provide 'ebp-sync-test)
;;; ebp-sync-test.el ends here
