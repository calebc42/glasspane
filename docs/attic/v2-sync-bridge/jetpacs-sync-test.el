;;; jetpacs-sync-test.el --- Tests for live editor synchronization -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Unit tests for `jetpacs-sync', verifying semantic role mapping,
;; sorted fontification spans, and echo-free track-changes coordination.

;;; Code:

(require 'ert)
(require 'jetpacs-sync)

(ert-deftest jetpacs-sync-test-role-for-face ()
  "Ensure common Emacs faces map directly to semantic role tokens."
  (should (equal "keyword" (jetpacs-sync--role-for-face 'font-lock-keyword-face)))
  (should (equal "string" (jetpacs-sync--role-for-face 'font-lock-string-face)))
  (should (equal "comment" (jetpacs-sync--role-for-face 'font-lock-comment-face)))
  (should (equal "function" (jetpacs-sync--role-for-face 'font-lock-function-name-face)))
  (should (equal "custom" (jetpacs-sync--role-for-face 'font-lock-custom-face)))
  (should (equal "default" (jetpacs-sync--role-for-face nil))))

(ert-deftest jetpacs-sync-test-fontify-runs-sorted-and-disjoint ()
  "Ensure extracted style spans are sorted, half-open, and non-overlapping."
  (with-temp-buffer
    (insert "def foo(x):")
    ;; Emacs positions are 1-based:
    ;; "def" -> [1..4) -> 0-based start=0, end=3
    (put-text-property 1 4 'face 'font-lock-keyword-face)
    ;; "foo" -> [5..8) -> 0-based start=4, end=7
    (put-text-property 5 8 'face 'font-lock-function-name-face)
    (let ((runs (jetpacs-sync--fontify-runs (current-buffer))))
      (should (equal 2 (length runs)))
      (let ((r1 (car runs))
            (r2 (cadr runs)))
        (should (equal 0 (plist-get r1 :start)))
        (should (equal 3 (plist-get r1 :end)))
        (should (equal "keyword" (plist-get r1 :role)))
        (should (equal 4 (plist-get r2 :start)))
        (should (equal 7 (plist-get r2 :end)))
        (should (equal "function" (plist-get r2 :role)))
        (should (<= (plist-get r1 :end) (plist-get r2 :start)))))))

(ert-deftest jetpacs-sync-test-echo-loop-prevention ()
  "Incoming wire changes must apply without echoing out via track-changes."
  (let* ((client 'mock-client)
         (doc "doc:test")
         (eid "main.py")
         (applied-splices nil))
    (cl-letf (((symbol-function 'ebp-client-edit-apply)
               (lambda (_c _d _e start del text)
                 (push (list start del text) applied-splices))))
      (let ((session (jetpacs-sync-on-edit-open client doc eid "print('hi')\n" nil)))
        (should session)
        (let ((buf (plist-get session :buffer)))
          (should (buffer-live-p buf))
          (with-current-buffer buf
            (should (string= "print('hi')\n" (buffer-string))))
          ;; Simulate mobile sending a delta/change
          (jetpacs-sync-on-edit-change client doc eid "print('hi mobile')\n")
          (with-current-buffer buf
            (should (string= "print('hi mobile')\n" (buffer-string))))
          ;; If echo prevention worked, track-changes was drained during apply,
          ;; so applied-splices must remain empty.
          (should (null applied-splices))
          ;; Now simulate autonomous Emacs modification in the buffer
          (with-current-buffer buf
            (goto-char (point-max))
            (insert "# comment\n"))
          ;; Trigger signal callback explicitly as track-changes would
          (jetpacs-sync--on-buffer-change (cons client (cons doc eid))
                                          (plist-get session :tracker))
          ;; Autonomous Emacs change MUST emit an edit.apply request
          (should (= 1 (length applied-splices)))
          (let ((splice (car applied-splices)))
            (should (equal 19 (nth 0 splice))) ; start offset
            (should (equal 0 (nth 1 splice)))  ; deleted characters
            (should (equal "# comment\n" (nth 2 splice))))
          (jetpacs-sync-on-edit-close client doc eid)
          (should (not (buffer-live-p buf))))))))

(provide 'jetpacs-sync-test)
;;; jetpacs-sync-test.el ends here
