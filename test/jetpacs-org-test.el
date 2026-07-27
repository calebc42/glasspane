;;; jetpacs-org-test.el --- JA-4 exit gate: the org engine -*- lexical-binding: t; -*-

;;; Commentary:

;; The JA-4 exit gate (docs/PLAN-jetpacs-apps.md JA-4) plus the biting
;; regressions for the twelve poc defects fixed at the port.  Fixtures
;; are temp .org files (the hypertext-test shape) with
;; `jetpacs-org-roots' let-bound to the temp directory — resolve-ref's
;; root allowlist refuses everything else by design, so EVERY test that
;; resolves goes through `jetpacs-org-test--with-fixture'.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'jetpacs-org)

(defmacro jetpacs-org-test--with-fixture (var content &rest body)
  "Write CONTENT to a temp .org file, bind VAR to its truename, run BODY.
Binds `jetpacs-org-roots' to the file's directory so resolve-ref admits
it, visits are cleaned up, and engine state is reset around BODY."
  (declare (indent 2))
  `(let* ((,var (file-truename
                 (make-temp-file "ja4-fixture" nil ".org" ,content)))
          (jetpacs-org-roots (list (file-name-directory ,var))))
     (unwind-protect
         (progn ,@body)
       (when-let* ((buf (find-buffer-visiting ,var)))
         (with-current-buffer buf (set-buffer-modified-p nil))
         (kill-buffer buf))
       (delete-file ,var)
       (jetpacs-org-reset))))

(defconst jetpacs-org-test--two-headings
  "* TODO First heading\nBody one.\n* Second heading\n:PROPERTIES:\n:ID: ja4-test-id-1\n:END:\nBody two.\n")

(defun jetpacs-org-test--ref-to (file headline)
  "A ref plist for HEADLINE in FILE, minted through the real API."
  (with-current-buffer (find-file-noselect file)
    (org-mode)
    (org-with-wide-buffer
     (goto-char (point-min))
     (search-forward headline)
     (jetpacs-org-ref-at-point))))

;;;; Refs and resolution

(ert-deftest jetpacs-org-ref-roundtrip-and-float-pos ()
  "A minted ref resolves back to its heading; a float :pos (the JSON
round-trip shape) still takes the trusted-position path."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (let ((ref (jetpacs-org-test--ref-to f "First heading")))
      ;; nth 4 of org-heading-components excludes the TODO keyword.
      (should (equal (plist-get ref :headline) "First heading"))
      (let ((m (jetpacs-org-resolve-ref ref)))
        (should (markerp m))
        (set-marker m nil))
      ;; Float pos coerces rather than falling to the headline scan.
      (let* ((fref (plist-put (copy-sequence ref) :pos
                              (float (plist-get ref :pos))))
             (m (jetpacs-org-resolve-ref fref)))
        (should (markerp m))
        (set-marker m nil)))))

(ert-deftest jetpacs-org-resolve-refuses-remote-before-any-stat ()
  "Defect 5: `file-remote-p' runs FIRST — the stat IS the connection.
A remote ref is refused with ZERO stat-family calls."
  (let ((stats 0))
    (cl-letf* ((record (lambda (real)
                         (lambda (&rest args)
                           (cl-incf stats) (apply real args))))
               ((symbol-function 'file-readable-p)
                (funcall record (symbol-function 'file-readable-p)))
               ((symbol-function 'file-truename)
                (funcall record (symbol-function 'file-truename)))
               ((symbol-function 'file-attributes)
                (funcall record (symbol-function 'file-attributes))))
      (should (eq 'jetpacs-org-refused
                  (condition-case err
                      (progn (jetpacs-org-resolve-ref
                              '(:id nil :file "/ssh:evil:/x.org"
                                :pos 1 :headline "h"))
                             :no-signal)
                    (jetpacs-org-refused (car err)))))
      (should (= stats 0)))))

(ert-deftest jetpacs-org-resolve-refuses-outside-roots ()
  "Defect 5: a path outside `jetpacs-org-roots' is refused, and by path
COMPONENTS — /tmp-evil is not under /tmp."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    ;; Same file, but the allowlist points elsewhere.
    (let ((jetpacs-org-roots (list (file-truename
                                    (make-temp-file "ja4-other" t)))))
      (should (eq 'jetpacs-org-refused
                  (condition-case err
                      (progn (jetpacs-org-resolve-ref
                              (list :id nil :file f :pos 1 :headline ""))
                             :no-signal)
                    (jetpacs-org-refused (car err))))))))

(ert-deftest jetpacs-org-resolve-never-triggers-an-org-id-rescan ()
  "Defect 5: the poc's `org-id-find' ran a FULL org-id rescan on a miss.
A bogus :id with a good position must resolve via the position and the
rescan trap must never fire."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (cl-letf (((symbol-function 'org-id-update-id-locations)
               (lambda (&rest _) (error "RESCAN — the org-id-find path"))))
      (let* ((ref (jetpacs-org-test--ref-to f "First heading"))
             (bogus (plist-put (copy-sequence ref) :id "no-such-id"))
             (m (jetpacs-org-resolve-ref bogus)))
        (should (markerp m))
        (set-marker m nil)))))

(ert-deftest jetpacs-org-errors-carry-no-paths ()
  "Defect 12: neither refusal nor unresolved errors embed the path."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (dolist (ref (list (list :id nil :file "/ssh:h:/secret.org"
                             :pos 1 :headline "h")
                       (list :id nil :file f :pos 999999
                             :headline "No Such Heading Anywhere")))
      (let ((err (condition-case e
                     (progn (jetpacs-org-resolve-ref ref) nil)
                   (error e))))
        (should err)
        (should-not (string-search "secret" (format "%S" err)))
        (should-not (string-search (file-name-nondirectory f)
                                   (format "%S" err)))))))

;;;; Tokens (D-4)

(ert-deftest jetpacs-org-tokens-are-opaque-and-owner-scoped ()
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (let* ((ref (jetpacs-org-test--ref-to f "First heading"))
           (tokens (jetpacs-org-ref-tokens (list ref)
                                           :set "s1" :owner "ja4a")))
      (should (= (length tokens) 1))
      ;; No path material in the token string.
      (should-not (string-search (file-name-nondirectory f) (car tokens)))
      ;; Resolves for its owner...
      (should (equal (jetpacs-org-token-ref (car tokens) :owner "ja4a")
                     ref))
      ;; ...and for nobody else, nor for garbage input.
      (should-not (jetpacs-org-token-ref (car tokens) :owner "ja4b"))
      (should-not (jetpacs-org-token-ref 42 :owner "ja4a"))
      (should-not (jetpacs-org-token-ref "o-forged-1" :owner "ja4a")))))

(ert-deftest jetpacs-org-token-remint-sweeps-the-old-generation ()
  "The replace-set contract: re-minting a set kills its old tokens —
a swept token is a plain miss the handler answers as `stale'."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (let* ((ref (jetpacs-org-test--ref-to f "First heading"))
           (old (car (jetpacs-org-ref-tokens (list ref)
                                             :set "s" :owner "ja4")))
           (new (car (jetpacs-org-ref-tokens (list ref)
                                             :set "s" :owner "ja4"))))
      (should-not (equal old new))
      (should-not (jetpacs-org-token-ref old :owner "ja4"))
      (should (jetpacs-org-token-ref new :owner "ja4"))
      ;; Table size stayed = the live set.
      (should (= (hash-table-count jetpacs-org--tokens) 1)))))

(ert-deftest jetpacs-org-token-teardown-sweeps-the-owner ()
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (let* ((ref (jetpacs-org-test--ref-to f "First heading"))
           (mine (car (jetpacs-org-ref-tokens (list ref)
                                              :set "s" :owner "gone")))
           (theirs (car (jetpacs-org-ref-tokens (list ref)
                                                :set "s" :owner "stays"))))
      (jetpacs-org--on-teardown "gone")
      (should-not (jetpacs-org-token-ref mine :owner "gone"))
      (should (jetpacs-org-token-ref theirs :owner "stays")))))

(ert-deftest jetpacs-org-token-mint-validates-refs ()
  "A policy-violating ref signals at MINT time, not at tap time."
  (should-error (jetpacs-org-ref-tokens
                 (list '(:id nil :file "/ssh:h:/x.org" :pos 1 :headline ""))
                 :set "s" :owner "ja4")
                :type 'jetpacs-org-refused))

;;;; The cache

(ert-deftest jetpacs-org-cache-hit-miss-invalidate ()
  "The with-cache gate: one body run, a hit, re-run on invalidate,
re-run on date roll."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (let ((runs 0)
          (org-agenda-files (list f)))
      (cl-flet ((probe () (jetpacs-org-with-cache "ja4t" (list 'k)
                            (cl-incf runs))))
        (probe) (probe)
        (should (= runs 1))
        (jetpacs-org-cache-invalidate "ja4t")
        (probe)
        (should (= runs 2))
        ;; Date roll busts the key.
        (cl-letf (((symbol-function 'format-time-string)
                   (lambda (&rest _) "2099-01-01")))
          (probe))
        (should (= runs 3))))))

(ert-deftest jetpacs-org-cache-key-sees-subsecond-and-membership ()
  "Defect 9: full-resolution stamps — two writes inside one float tick
yield distinct keys, and DROPPING a file changes the key even when the
remaining max mtime is unchanged (the poc's max-float was blind to
both)."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (let ((g (file-truename
              (make-temp-file "ja4-second" nil ".org" "* Other\n"))))
      (unwind-protect
          (progn
            ;; Distinct sub-second mtimes on the same integer second.
            (set-file-times f (encode-time '(0 0 0 1 1 2026 nil nil 0)))
            (let ((jetpacs-org--stamp-memo nil)
                  (org-agenda-files (list f)))
              (let ((k1 (jetpacs-org--cache-key "ns")))
                (set-file-times
                 f (time-add (encode-time '(0 0 0 1 1 2026 nil nil 0))
                             '(0 0 500000 0)))    ; +0.5ms, same second
                (setq jetpacs-org--stamp-memo nil)
                (let ((k2 (jetpacs-org--cache-key "ns")))
                  (should-not (equal k1 k2)))))
            ;; Membership: drop a file whose mtime is NOT the max.
            (set-file-times g (encode-time '(0 0 0 1 1 2020 nil nil 0)))
            (let ((jetpacs-org--stamp-memo nil))
              (let* ((org-agenda-files (list f g))
                     (k-both (jetpacs-org--cache-key "ns")))
                (setq jetpacs-org--stamp-memo nil)
                (let* ((org-agenda-files (list f))
                       (k-one (jetpacs-org--cache-key "ns")))
                  (should-not (equal k-both k-one))))))
        (delete-file g)))))

(ert-deftest jetpacs-org-cache-stat-memo-bounds-the-sweep ()
  "Defect 9: consecutive lookups within the TTL run ONE stat sweep;
invalidate clears the memo so a mutation is never masked."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (let ((stats 0)
          (org-agenda-files (list f))
          (jetpacs-org--stamp-memo nil))
      (cl-letf* ((real (symbol-function 'file-attributes))
                 ((symbol-function 'file-attributes)
                  (lambda (&rest args) (cl-incf stats) (apply real args))))
        (jetpacs-org--cache-key "ns")
        (jetpacs-org--cache-key "ns")
        (should (= stats 1))
        (jetpacs-org-cache-invalidate)
        (jetpacs-org--cache-key "ns")
        (should (= stats 2))))))

;;;; Mutations

(ert-deftest jetpacs-org-with-mutation-escapes-narrowing ()
  "Defect 8: a mutation lands on ITS heading even when the buffer is
narrowed to a different one, and the narrowing survives."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (let ((ref (jetpacs-org-test--ref-to f "Second heading")))
      (with-current-buffer (find-file-noselect f)
        (widen)
        (goto-char (point-min))
        (org-narrow-to-subtree)             ; narrowed to First
        (let ((before (cons (point-min) (point-max))))
          (jetpacs-org-set-property ref "ja4t" "MOOD" "good")
          (should (equal before (cons (point-min) (point-max)))))
        (org-with-wide-buffer
         (goto-char (point-min))
         (search-forward "Second heading")
         (should (equal (org-entry-get (point) "MOOD") "good")))))))

(ert-deftest jetpacs-org-toggle-todo-flushes-a-time-note ()
  "Exit-gate half A: under `org-log-done' `time', the toggle writes the
CLOSED stamp inline and leaves NO pending note machinery."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (let ((ref (jetpacs-org-test--ref-to f "First heading"))
          (org-log-done 'time)
          (org-todo-keywords '((sequence "TODO" "DONE"))))
      (jetpacs-org-toggle-todo ref "ja4t" "DONE")
      (with-current-buffer (find-file-noselect f)
        (org-with-wide-buffer
         (goto-char (point-min))
         (should (search-forward "CLOSED:" nil t))))
      (should-not (bound-and-true-p org-log-setup))
      (should-not (memq 'org-add-log-note post-command-hook)))))

(ert-deftest jetpacs-org-toggle-todo-never-pops-a-note-buffer ()
  "Defect 2: under `org-log-done' `note' the poc popped a modal
*Org Note* nobody on the device can C-c C-c, and the LOGBOOK line was
never written.  The gate cancels instead: no note buffer, no pending
setup, no hook left armed."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (let ((ref (jetpacs-org-test--ref-to f "First heading"))
          (org-log-done 'note)
          (org-todo-keywords '((sequence "TODO" "DONE")))
          (inhibit-message t))
      (jetpacs-org-toggle-todo ref "ja4t" "DONE")
      (should-not (get-buffer "*Org Note*"))
      (should-not (bound-and-true-p org-log-setup))
      (should-not (memq 'org-add-log-note post-command-hook))
      ;; The state change itself landed.
      (with-current-buffer (find-file-noselect f)
        (org-with-wide-buffer
         (goto-char (point-min))
         (should (looking-at-p "\\* DONE ")))))))

(ert-deftest jetpacs-org-set-planning-roundtrip ()
  "The undocumented `org-add-planning-info' idioms this module depends
on, pinned: symbol type to set, trailing remove-arg to clear."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (let ((ref (jetpacs-org-test--ref-to f "First heading")))
      (jetpacs-org-set-planning ref "ja4t" "SCHEDULED" "<2026-08-01 Sat>")
      (with-current-buffer (find-file-noselect f)
        (org-with-wide-buffer
         (goto-char (point-min))
         (should (search-forward "SCHEDULED: <2026-08-01" nil t))))
      (jetpacs-org-set-planning ref "ja4t" "SCHEDULED" nil)
      (with-current-buffer (find-file-noselect f)
        (org-with-wide-buffer
         (goto-char (point-min))
         (should-not (search-forward "SCHEDULED:" nil t)))))))

;;;; The deferred save

(ert-deftest jetpacs-org-defer-save-debounces ()
  "Defect 3: five mutations arm ONE timer, not five."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (with-current-buffer (find-file-noselect f)
      (dotimes (_ 5) (jetpacs-org-defer-save))
      (should (timerp jetpacs-org--save-timer))
      ;; Idle timers live on `timer-idle-list', not `timer-list'.
      (should (= 1 (cl-count-if
                    (lambda (tm) (eq (timer--function tm)
                                     #'jetpacs-org--save-now))
                    timer-idle-list))))))

(ert-deftest jetpacs-org-defer-save-refuses-superseded-file ()
  "Defect 3: the save body must refuse a superseded file rather than
reach `basic-save-buffer's `yes-or-no-p' — a prompt in a timer wedges a
daemon."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--two-headings
    (let ((buf (find-file-noselect f))
          (inhibit-message t))
      (with-current-buffer buf
        (goto-char (point-max))
        (insert "edit\n"))                       ; modified
      ;; Supersede on disk behind the buffer's back.
      (with-temp-file f (insert "* Replaced\n"))
      (cl-letf (((symbol-function 'yes-or-no-p)
                 (lambda (&rest _) (error "PROMPT reached in a timer")))
                ((symbol-function 'ask-user-about-supersession-threat)
                 (lambda (&rest _) (error "PROMPT reached in a timer"))))
        (jetpacs-org--save-now buf))
      ;; Refused: still modified, disk content untouched.
      (should (buffer-modified-p buf))
      (with-temp-buffer
        (insert-file-contents f)
        (should (equal (buffer-string) "* Replaced\n")))
      (with-current-buffer buf (set-buffer-modified-p nil)))))

;;;; Typed extraction

(ert-deftest jetpacs-org-typed-values ()
  (jetpacs-org-test--with-fixture f
      "* H\n:PROPERTIES:\n:DONE_BOX: [X]\n:COUNT: 42\n:KIND: b\n:KIND_ALL: a b c\n:BAD: z\n:BAD_ALL: a b c\n:LABELS: x, y z\n:END:\n"
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (org-with-wide-buffer
       (goto-char (point-min))
       (should (eq (jetpacs-org-entry-typed-value "DONE_BOX" 'checkbox) t))
       (should (= (jetpacs-org-entry-typed-value "COUNT" 'number) 42))
       (should (equal (jetpacs-org-entry-typed-value "KIND" 'enum) "b"))
       (should-not (jetpacs-org-entry-typed-value "BAD" 'enum))
       (should (equal (jetpacs-org-entry-typed-value "LABELS" 'list)
                      '("x" "y" "z")))
       (should (equal (jetpacs-org-entry-typed-value "MISSING" 'text) ""))))))

(provide 'jetpacs-org-test)
;;; jetpacs-org-test.el ends here
