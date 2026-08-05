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

(provide 'ebp-sync-test)
;;; ebp-sync-test.el ends here
