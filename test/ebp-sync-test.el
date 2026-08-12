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

(provide 'ebp-sync-test)
;;; ebp-sync-test.el ends here
