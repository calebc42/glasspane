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

(defvar jetpacs-org-test--sexp-ran nil
  "Set by a hostile capture payload if the escape ever fails.")

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

(ert-deftest jetpacs-org-configuration-never-dials-a-remote-name ()
  "JA-4 audit P1-7: the remote guard was applied to the ref's own name but
NOT to the configuration the guard reads.  `org-agenda-files' calls
`file-directory-p' on every raw entry, so one /ssh: entry dialled TRAMP
on every resolve, every mint, and — via the cache stamp — every query,
inside the socket filter against a 60s timeout.  No stat-family
primitive may receive a remote NAME on any of the three hot paths."
  (jetpacs-org-test--with-fixture f "* TODO H\n"
    (let ((touched '()))
      (cl-letf* ((watch (lambda (real)
                          (lambda (&rest args)
                            (when (and (stringp (car args))
                                       (file-remote-p (car args)))
                              (push (car args) touched))
                            (apply real args))))
                 ((symbol-function 'file-directory-p)
                  (funcall watch (symbol-function 'file-directory-p)))
                 ((symbol-function 'file-truename)
                  (funcall watch (symbol-function 'file-truename)))
                 ((symbol-function 'file-exists-p)
                  (funcall watch (symbol-function 'file-exists-p)))
                 ((symbol-function 'file-attributes)
                  (funcall watch (symbol-function 'file-attributes)))
                 ((symbol-function 'file-readable-p)
                  (funcall watch (symbol-function 'file-readable-p))))
        (let* ((org-directory (file-name-directory f))
               (org-agenda-files (list f "/ssh:evil:/remote.org"))
               ;; nil forces the DERIVED root set — the path that read
               ;; configuration without filtering it.
               (jetpacs-org-roots nil))
          (jetpacs-org-cache-invalidate)
          (jetpacs-org--files-stamp)      ; hot path 1: the cache key
          (jetpacs-org--roots)            ; hot path 2: the allowlist
          (jetpacs-org--check-file f)     ; hot path 3: every resolve/mint
          (should (null touched)))))))

(ert-deftest jetpacs-org-check-file-rides-the-floor-guard ()
  "The sandbox itself lives on the floor (JA-6 shares it); this module
supplies roots and re-signals in its own condition, so a handler written
against the documented status map never sees `jetpacs-path-refused'."
  (jetpacs-org-test--with-fixture f "* H\n"
    (should (equal (jetpacs-org--check-file f) (file-truename f)))
    (dolist (bad '("relative.org" "/ssh:evil:/x.org" "/etc/passwd"))
      (should (eq 'jetpacs-org-refused
                  (condition-case err
                      (progn (jetpacs-org--check-file bad) :no-signal)
                    (jetpacs-org-refused (car err))
                    (jetpacs-path-refused (car err))))))
    ;; An unconfigured root set is distinguishable from out-of-policy.
    (should (eq 'no-roots
                (let ((jetpacs-org-roots '("/nonexistent-root-xyz")))
                  (condition-case err
                      (progn (jetpacs-org--check-file f) :no-signal)
                    (jetpacs-org-refused (cadr err))))))))

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

;;;; The query grammar (O2)

(defconst jetpacs-org-test--agenda
  "* TODO Pay the bill :money:\nSCHEDULED: <2026-08-01 Sat>\nelectric company\n* NEXT Call Alice :work:\n* DONE Old chore :money:\nCLOSED: [2026-07-01 Wed]\n* Plain notes\nnothing actionable\n* TODO [#A] Urgent thing :work:\n"
  "Decoy-laden: every clause below matches SOME entry; only the
conjunction picks exactly one — an accidentally-OR interpreter fails.")

(defmacro jetpacs-org-test--with-agenda (var &rest body)
  (declare (indent 1))
  `(jetpacs-org-test--with-fixture ,var jetpacs-org-test--agenda
     (let ((org-agenda-files (list ,var))
           (org-todo-keywords '((sequence "TODO" "NEXT" "|" "DONE"))))
       ,@body)))

(defun jetpacs-org-test--titles (tree)
  "Run TREE end-to-end through the REAL entry point; titles returned."
  (jetpacs-org-query "ja4-test" tree
                     (lambda () (nth 4 (org-heading-components)))))

(ert-deftest jetpacs-org-grammar-sexp-conjunction ()
  "Exit gate G1 (sexp): decoys match single clauses; the conjunction
picks exactly one entry."
  (jetpacs-org-test--with-agenda f
    (should (equal (jetpacs-org-test--titles
                    (jetpacs-org-parse-query
                     "(and (todo \"TODO\") (tags \"money\"))"))
                   '("Pay the bill")))
    ;; OR spans; NOT excludes.
    (should (= 2 (length (jetpacs-org-test--titles
                          (jetpacs-org-parse-query
                           "(and (todo) (tags \"work\"))")))))
    (should (equal (jetpacs-org-test--titles
                    (jetpacs-org-parse-query
                     "(and (tags \"money\") (not (done)))"))
                   '("Pay the bill")))))

(ert-deftest jetpacs-org-grammar-tokens ()
  "Exit gate G1 (tokens) incl. `priority:' — present in the grammar,
omitted by the plan's gate text."
  (jetpacs-org-test--with-agenda f
    (should (equal (jetpacs-org-test--titles
                    (jetpacs-org-parse-query "todo:TODO tags:work"))
                   '("Urgent thing")))
    (should (equal (jetpacs-org-test--titles
                    (jetpacs-org-parse-query "priority:A"))
                   '("Urgent thing")))
    (jetpacs-org-cache-invalidate)
    (should (equal (jetpacs-org-test--titles
                    (jetpacs-org-parse-query "todo:TODO,NEXT tags:work"))
                   '("Call Alice" "Urgent thing")))))

(ert-deftest jetpacs-org-grammar-freetext ()
  "Exit gate G1 (free text): quoted phrase + bare word, body haystack."
  (jetpacs-org-test--with-agenda f
    (should (equal (jetpacs-org-test--titles
                    (jetpacs-org-parse-query "\"electric company\""))
                   '("Pay the bill")))
    (should (equal (jetpacs-org-test--titles
                    (jetpacs-org-parse-query "nothing"))
                   '("Plain notes")))))

(ert-deftest jetpacs-org-grammar-planning-window ()
  "The :on/:from/:to plist arm over scheduled stamps."
  (jetpacs-org-test--with-agenda f
    (should (equal (jetpacs-org-test--titles
                    (jetpacs-org-parse-query
                     "(scheduled :on \"2026-08-01\")"))
                   '("Pay the bill")))
    (jetpacs-org-cache-invalidate)
    (should-not (jetpacs-org-test--titles
                 (jetpacs-org-parse-query
                  "(scheduled :from \"2026-09-01\")")))))

(ert-deftest jetpacs-org-query-vet-rejects-hostile-input ()
  "Defect 4 (SPEC 23.2): the rejects family, each through the REAL
`jetpacs-org-parse-query'."
  (dolist (q '("(delete-file \"/etc/passwd\")"     ; unknown head
               "(todo #[257 \"x\" [] 2])"          ; byte-code object
               "(todo #s(hash-table))"             ; record form
               "(priority > 1.5)"                  ; float
               "(scheduled :evil 1)"               ; stray keyword
               "(and (todo \"A\")) (tags \"b\")"   ; trailing 2nd form
               "'(and #1=(todo \"x\") #1#)"))     ; cycle labels (read-circle nil)
    (should-error (jetpacs-org-parse-query q) :type 'user-error))
  ;; A #1=-prefixed string never reaches the reader at all: the sexp
  ;; gate requires a leading paren, so it tokenizes into an inert regexp
  ;; query — assert the SAFE routing rather than a refusal.
  (should (eq (car (jetpacs-org-parse-query "#1=(and . #1#)")) 'and))
  ;; Depth and node caps.
  (should-error (jetpacs-org-parse-query
                 (concat (make-string 12 ?\() "todo \"x\""
                         (make-string 12 ?\))))
                :type 'user-error)
  (should-error (jetpacs-org-parse-query
                 (format "(and %s)"
                         (mapconcat (lambda (_) "(todo \"x\")")
                                    (number-sequence 1 100) " ")))
                :type 'user-error))

(ert-deftest jetpacs-org-query-vet-is-obarray-clean ()
  "Defect 4, the measured half: a hostile query's symbols never reach
the global obarray — even when the query is REFUSED."
  (should-not (intern-soft "ja4-gpzz-never-interned"))
  (condition-case nil
      (jetpacs-org-parse-query "(and (ja4-gpzz-never-interned 1))")
    (user-error nil))
  (should-not (intern-soft "ja4-gpzz-never-interned"))
  ;; And an ACCEPTED query's argument symbols become strings, not interns.
  (should-not (intern-soft "ja4-gpzz-arg-sym"))
  (should (equal (jetpacs-org-parse-query "(todo ja4-gpzz-arg-sym)")
                 '(todo "ja4-gpzz-arg-sym")))
  (should-not (intern-soft "ja4-gpzz-arg-sym")))

(ert-deftest jetpacs-org-query-vet-normalizes-like-the-poc ()
  "Quote unwrapping, literal preservation, bare-symbol stringification."
  (should (equal (jetpacs-org-parse-query "'(todo TODO)")
                 '(todo "TODO")))
  (should (equal (jetpacs-org-parse-query "(priority > \"B\")")
                 '(priority > "B")))
  (should (equal (jetpacs-org-parse-query "(scheduled :from today :to 7)")
                 '(scheduled :from today :to 7)))
  ;; Re-homed heads are the CANONICAL symbols (eq, not just equal).
  (should (eq (car (jetpacs-org-parse-query "(todo \"X\")")) 'todo)))

(defun jetpacs-org-test--tree-canonical-p (x)
  "Non-nil when every symbol in tree X is the canonical global intern
and every string carries zero text properties over its whole length."
  (cond
   ((consp x) (and (jetpacs-org-test--tree-canonical-p (car x))
                   (jetpacs-org-test--tree-canonical-p (cdr x))))
   ((symbolp x) (eq x (intern-soft (symbol-name x))))
   ((stringp x)
    (cl-loop for i below (length x)
             always (null (text-properties-at i x))))
   (t t)))

(ert-deftest jetpacs-org-query-vet-refuses-wire-regexp ()
  "JA-4 audit P1-2 (SPEC #137): `regexp' is interpreter vocabulary, not
wire vocabulary — a wire (regexp …) hands the peer a raw regexp engine
\(ReDoS at will).  `heading' regexp-quotes and covers the use case, and
the token arm still mints its own regexp clauses from quoted material."
  (dolist (q '("(regexp \"x\")"
               "(regexp \"\\\\(a*\\\\)*b\")"))
    (let ((err (should-error (jetpacs-org-parse-query q)
                             :type 'user-error)))
      (should (equal (cadr err) "Unsupported query term"))))
  ;; Positive control: free text still routes through the token arm.
  (should (equal (jetpacs-org-parse-query "foo") '(regexp "foo"))))

(ert-deftest jetpacs-org-query-vet-strips-text-properties ()
  "JA-4 audit P1-3: the reader mints PROPERTIZED strings from #(…) wire
text, with throwaway-obarray symbols riding in the property list; the
vetter's output invariant promises fresh propertyless strings, so
enforce it end to end through the public entry point."
  (let ((tree (jetpacs-org-parse-query
               "(todo #(\"x\" 0 1 (ja4-smug ja4-val)))")))
    (should (equal tree '(todo "x")))
    (should (jetpacs-org-test--tree-canonical-p tree)))
  ;; Symbols in the output are the canonical global interns.
  (should (jetpacs-org-test--tree-canonical-p
           (jetpacs-org-parse-query
            "(and (todo KW) (scheduled :from today))"))))

(ert-deftest jetpacs-org-parse-query-caps-govern-both-arms ()
  "JA-4 audit P1-4: the caps sat on the sexp arm only — the token arm
had no length bound at all, and the empty quoted phrase minted a
match-everything (regexp \"\") clause."
  ;; Token arm: over-length refuses before tokenizing.
  (let ((err (should-error (jetpacs-org-parse-query (make-string 201 ?a))
                           :type 'user-error)))
    (should (equal (cadr err) "Query too long")))
  ;; Sexp arm: the SAME cap, before the reader runs.
  (let ((err (should-error
              (jetpacs-org-parse-query
               (concat "(todo \"" (make-string 200 ?x) "\")"))
              :type 'user-error)))
    (should (equal (cadr err) "Query too long")))
  ;; The empty quoted phrase never mints (regexp "") — nor a bare (and).
  (should-not (jetpacs-org-parse-query "\"\""))
  (should (equal (jetpacs-org-parse-query "\"\" x") '(regexp "x")))
  ;; Real depth coverage: nesting ALONE trips the cap (the hostile-input
  ;; test's paren tower dies as a malformed clause before depth counts).
  (let ((err (should-error
              (jetpacs-org-parse-query
               (concat (apply #'concat (make-list 12 "(not "))
                       "(todo \"x\")"
                       (make-string 12 ?\))))
              :type 'user-error)))
    (should (equal (cadr err) "Query too deep"))))

(ert-deftest jetpacs-org-query-vet-checks-arity-and-types ()
  "The per-head arity/type schema, and its refusal wording: the head
symbol at most, NEVER the query text (SPEC 23.3)."
  (pcase-dolist (`(,q . ,msg)
                 '(("(done \"x\")"  . "Malformed done clause")
                   ("(not)"         . "Malformed not clause")
                   ("(habit 1)"     . "Malformed habit clause")
                   ("(level \"3\")" . "Malformed level clause")
                   ("(and \"x\")"   . "Malformed query clause")))
    (let ((err (should-error (jetpacs-org-parse-query q)
                             :type 'user-error)))
      (should (equal (cadr err) msg))))
  (let ((err (should-error
              (jetpacs-org-parse-query "(level 3 \"SNEAKPAYLOAD\")")
              :type 'user-error)))
    (should (equal (cadr err) "Malformed level clause"))
    (should-not (string-search "SNEAKPAYLOAD" (format "%S" err)))))

(ert-deftest jetpacs-org-query-vet-refuses-special-properties ()
  "Every `org-special-properties' name is path/derived data with a
dedicated grammar head; (property \"FILE\") would leak absolute paths
through a grammar that promises path-free results."
  (dolist (q '("(property \"FILE\")"
               "(property \"file\")"
               "(property \"TODO\" \"x\")"))
    (let ((err (should-error (jetpacs-org-parse-query q)
                             :type 'user-error)))
      (should (equal (cadr err) "Unsupported property name"))))
  ;; Ordinary properties still pass, with and without a value.
  (should (equal (jetpacs-org-parse-query "(property \"MOOD\" \"good\")")
                 '(property "MOOD" "good")))
  (should (equal (jetpacs-org-parse-query "(property \"MOOD\")")
                 '(property "MOOD"))))

(ert-deftest jetpacs-org-priority-comparator-inverts ()
  "org urgency runs A > B > C: the comparator flips against the chars."
  (jetpacs-org-test--with-agenda f
    ;; "higher than B" must return the #A entry.
    (should (equal (jetpacs-org-test--titles
                    (jetpacs-org-parse-query "(priority > \"B\")"))
                   '("Urgent thing")))))

;;;; Shared primitives (O3)

(ert-deftest jetpacs-org-ts-extractors ()
  (should (equal (jetpacs-org-ts-date "<2026-08-01 Sat 14:30 +1w>")
                 "2026-08-01"))
  (should (equal (jetpacs-org-ts-time "<2026-08-01 Sat 14:30 +1w>")
                 "14:30"))
  (should (equal (jetpacs-org-ts-repeater "<2026-08-01 Sat .+2d>") ".+2d"))
  ;; Delay cookies deliberately do not match.
  (should-not (jetpacs-org-ts-repeater "<2026-08-01 Sat -1d>"))
  (should-not (jetpacs-org-ts-date nil)))

(ert-deftest jetpacs-org-capture-prompts-schema ()
  "Exit-gate: the ONE extractor (D-5 dedupe) — %? adds Headline,
defaults drop from labels, duplicates collapse."
  (should (equal (jetpacs-org-capture-prompts
                  "* %^{Title|untitled} %? %^{Title} %^{Tag}")
                 '("Headline" "Title" "Tag")))
  (should (equal (jetpacs-org-capture-prompts "* plain") '())))

(ert-deftest jetpacs-org-capture-fill-precedence ()
  "User value > template default > empty; leftover carets stripped.
Wire values are SENTINELS in the returned text (they are installed after
expansion); a template default is the user's own config and is inlined."
  (let* ((pair (jetpacs-org-capture-fill
                "* %^{Title|dflt} %?\n%^t %^{Empty}"
                '(("Title" . "mine") ("Headline" . "H"))))
         (text (car pair))
         (bindings (cdr pair)))
    ;; Both wire values deferred, neither present as literal text.
    (should-not (string-search "mine" text))
    (should-not (string-search "H" text))
    (should (equal (sort (mapcar #'cdr bindings) #'string<) '("H" "mine")))
    ;; Substituting the sentinels back reproduces the old expectation.
    (dolist (b bindings)
      (setq text (replace-regexp-in-string (regexp-quote (car b))
                                           (cdr b) text t t)))
    (should (equal text "* mine H\n "))))

(ert-deftest jetpacs-org-capture-values-are-data-not-template ()
  "JA-4 audit P1-1.  A wire value is substituted only AFTER org-capture
has finished expanding, so no peer text can become template source:
`%(sexp)' must not evaluate, `%[PATH]' must not read a file, and a
literal \\=\\1 or & must not act as replacement-template syntax.  The
regression half matters as much: the USER'S OWN template escapes must
still work, or the fix has bought safety by removing the feature."
  (jetpacs-org-test--with-fixture target "* Inbox\n"
    (let ((secret (expand-file-name "ja4-secret.txt"
                                    (file-name-directory target))))
      (unwind-protect
          (progn
            (with-temp-file secret (insert "TOP-SECRET-PAYLOAD\n"))
            (setq jetpacs-org-test--sexp-ran nil)
            (let ((org-capture-templates
                   `(("t" "T" entry (file ,target) "* TODO %^{Title}\n%?")
                     ;; The user's own template, exercising org's power.
                     ("u" "U" entry (file ,target)
                      "* TODO %^{Title} :: %(concat \"tmpl\" \"-sexp-ok\")\n%?"))))
              (jetpacs-org-capture-run
               "t" `(("Title" . "hi %(progn (setq jetpacs-org-test--sexp-ran t) \"OWNED\")")
                     ("Headline" . "body")))
              (jetpacs-org-capture-run
               "t" `(("Title" . ,(format "x %%[%s]" secret)) ("Headline" . "b")))
              (jetpacs-org-capture-run
               "t" '(("Title" . "back\\1slash & amp") ("Headline" . "b")))
              (jetpacs-org-capture-run
               "t" '(("Title" . "shared") ("Headline" . "b"))
               "shared %(setq jetpacs-org-test--sexp-ran 'VIA-EXTRA-BODY)")
              (jetpacs-org-capture-run
               "u" '(("Title" . "legit") ("Headline" . "b"))))
            (let ((text (with-temp-buffer (insert-file-contents target)
                                          (buffer-string))))
              ;; Nothing from the wire ran, in either carrier.
              (should-not jetpacs-org-test--sexp-ran)
              (should (string-search "hi %(progn" text))
              (should (string-search "shared %(setq" text))
              ;; No local file was read into the user's org file.
              (should-not (string-search "TOP-SECRET-PAYLOAD" text))
              (should (string-search "%[" text))
              ;; replace-match LITERAL: \1 and & are inert.
              (should (string-search "back\\1slash & amp" text))
              ;; REGRESSION: the user's own template sexp still evaluates.
              (should (string-search "tmpl-sexp-ok" text))
              ;; And no scaffolding leaked into the file.
              (should-not (string-match-p "JPCAPZ" text))))
        (when (file-exists-p secret) (delete-file secret))))))

(ert-deftest jetpacs-org-capture-run-refuses-a-prefix-group ()
  "A 2-element entry is a legal PREFIX GROUP, not a template; indexing
`nth' 4 on one signalled wrong-type-argument."
  (let ((org-capture-templates '(("b" "Templates for buying"))))
    (should-error (jetpacs-org-capture-run "b" nil) :type 'user-error)))

(ert-deftest jetpacs-org-capture-run-real ()
  "Exit-gate G3: a REAL org-capture run into a temp target — user
values land, no residue, no lingering capture buffer, and the
filled-copy binding holds (defaults would show if the ORIGINAL entry
re-ran its prompts)."
  (jetpacs-org-test--with-fixture target "* Inbox\n"
    (let ((org-capture-templates
           `(("t" "Task" entry (file+headline ,target "Inbox")
              "* TODO %^{Title|default-title}\n%?"
              :immediate-finish nil))))   ; the defect-1 shape, on purpose
      (jetpacs-org-capture-run "t" '(("Title" . "user-title")
                                     ("Headline" . "the body line")))
      (with-temp-buffer
        (insert-file-contents target)
        (let ((text (buffer-string)))
          (should (string-search "* TODO user-title" text))
          (should (string-search "the body line" text))
          (should-not (string-search "default-title" text))
          (should-not (string-search "%^" text))))
      ;; :immediate-finish t WON over the template own nil — no capture
      ;; buffer is waiting for a C-c C-c.
      (should-not (cl-find-if (lambda (b)
                                (string-prefix-p "CAPTURE-" (buffer-name b)))
                              (buffer-list))))))

(ert-deftest jetpacs-org-capture-run-unknown-key-signals ()
  "The poc silently no-opped an unknown key — a capture that vanished."
  (let ((org-capture-templates (list (list "t" "Task" 'entry '(file "/dev/null") "x"))))
    (should-error (jetpacs-org-capture-run "zz" nil) :type 'user-error)))

(ert-deftest jetpacs-org-capture-templates-plist-shape ()
  (let ((org-capture-templates
         (list (list "t" "Task" 'entry '(file "x.org") "* %^{Who} %?"))))
    (let ((one (car (jetpacs-org-capture-templates))))
      (should (equal (plist-get one :key) "t"))
      (should (equal (plist-get one :description) "Task"))
      (should (equal (append (plist-get one :prompts) nil)
                     '("Headline" "Who"))))))

(ert-deftest jetpacs-org-parse-logbook-shapes ()
  "The five recognisers, in file order."
  (let ((entries (jetpacs-org-parse-logbook
                  (concat "CLOCK: [2026-07-01 Wed 10:00]--[2026-07-01 Wed 11:00] =>  1:00\n"
                          "CLOCK: [2026-07-27 Mon 09:00]\n"
                          "- Note taken on [2026-07-02 Thu 12:00] \\\\\n"
                          "  the note body\n"
                          "- State \"DONE\"       from \"TODO\"       [2026-07-03 Fri]\n"))))
    (should (= (length entries) 4))
    (should (equal (plist-get (nth 0 entries) :duration) "1:00"))
    (should (plist-get (nth 1 entries) :active))
    (should (equal (plist-get (nth 2 entries) :content) "the note body"))
    (let ((state (nth 3 entries)))
      (should (equal (plist-get state :to) "DONE"))
      (should (equal (plist-get state :from) "TODO"))
      (should-not (plist-get state :has-note)))))

(ert-deftest jetpacs-org-parse-logbook-clock-continuation ()
  "Defect 7: a continuation under a CLOCK entry (no :content) must not
grow a spurious leading newline off a nil."
  (let ((entries (jetpacs-org-parse-logbook
                  "CLOCK: [2026-07-27 Mon 09:00]\nstray continuation\n")))
    (should (= (length entries) 1))
    (should (equal (plist-get (car entries) :content)
                   "stray continuation"))))

(ert-deftest jetpacs-org-logbook-entries-reads-the-drawer ()
  (jetpacs-org-test--with-fixture f
      "* TODO H\n:LOGBOOK:\n- State \"DONE\" [2026-07-01 Tue]\n:END:\nBody.\n"
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (org-with-wide-buffer
       (let ((entries (jetpacs-org-logbook-entries (point-min))))
         (should (= (length entries) 1))
         (should (equal (plist-get (car entries) :to) "DONE")))))))

(ert-deftest jetpacs-org-set-repeater-roundtrip-and-unterminated ()
  "Add, replace, remove — and defect 6: an unterminated timestamp is a
NO-OP, byte-identical buffer, instead of search-failed escaping."
  (jetpacs-org-test--with-fixture f
      "* TODO H\nSCHEDULED: <2026-08-01 Sat>\n* Broken\nSCHEDULED: <2026-08-01\n"
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (org-with-wide-buffer
       (goto-char (point-min))
       (jetpacs-org-set-repeater "SCHEDULED" "+1w")
       (should (save-excursion (goto-char (point-min))
                               (search-forward "<2026-08-01 Sat +1w>" nil t)))
       (goto-char (point-min))
       (jetpacs-org-set-repeater "SCHEDULED" ".+2d")
       (should (save-excursion (goto-char (point-min))
                               (search-forward "<2026-08-01 Sat .+2d>" nil t)))
       (goto-char (point-min))
       (jetpacs-org-set-repeater "SCHEDULED" nil)
       (should-not (save-excursion (goto-char (point-min))
                                   (search-forward "+2d" nil t)))
       ;; The unterminated heading: no signal, no change.
       (search-forward "* Broken")
       (let ((before (buffer-string)))
         (jetpacs-org-set-repeater "SCHEDULED" "+1w")
         (should (equal (buffer-string) before))))
      (set-buffer-modified-p nil))))

(ert-deftest jetpacs-org-tblfm-field-over-column ()
  "Field formulas (@R$C) beat column formulas ($C), mirroring org."
  (jetpacs-org-test--with-fixture f
      "| a | b |\n|---+---|\n| 1 | 2 |\n| 3 | 4 |\n#+TBLFM: @3$2=@3$1*2::$2=$1+1\n"
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (org-with-wide-buffer
       (goto-char (point-min))
       (search-forward "| 3 | 4")
       (backward-char 1)
       (should (equal (car (jetpacs-org-table-field-formula)) "@3$2"))
       (goto-char (point-min))
       (search-forward "| 1 | 2")
       (backward-char 1)
       (should (equal (car (jetpacs-org-table-field-formula)) "$2"))))))

(ert-deftest jetpacs-org-format-clock-time-shapes ()
  (should (equal (jetpacs-org-format-clock-time
                  "2026-07-01 Wed 10:00" "2026-07-01 Wed 11:30")
                 "2026-07-01, 10:00 to 11:30"))
  (should (equal (jetpacs-org-format-clock-time
                  "2026-07-01 Wed 23:30" "2026-07-02 Thu 00:15")
                 "2026-07-01 23:30 to 2026-07-02 00:15"))
  ;; The degraded arm never signals.
  (should (stringp (jetpacs-org-format-clock-time "x" "y"))))

;;;; The outline model (JA-5a, amendment A3)

(defconst jetpacs-org-test--outline-fixture
  (concat "* One\nBody.\n"
          "** TODO [#A] Sub :tag:\nDEADLINE: <2026-01-01 Thu>\nSub body.\n"
          "* DONE Two\n"
          "*** Skip\n")
  "Two roots, a decorated child, and a SKIPPED level under Two.")

(ert-deftest jetpacs-org-outline-collect-records-fields ()
  "Collection walks every heading; records carry the decoded fields.
`include-first' picks up a heading sitting exactly at BEG."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--outline-fixture
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (org-with-wide-buffer
       (let ((recs (jetpacs-org-outline-collect (point-min) (point-max) nil)))
         (should (= 4 (length recs)))
         (let ((one (nth 0 recs)) (sub (nth 1 recs)) (two (nth 2 recs)))
           (should (equal (plist-get one :title) "One"))
           (should (= 1 (plist-get one :level)))
           (should-not (plist-get one :todo))
           (should (equal (plist-get sub :todo) "TODO"))
           (should (equal (plist-get sub :priority) "A"))
           (should (equal (plist-get sub :tags) '("tag")))
           (should-not (plist-get sub :done))
           (should (plist-get sub :deadline))
           (should (string-match-p "Sub body" (plist-get sub :body)))
           (should (equal (plist-get two :todo) "DONE"))
           (should (plist-get two :done))))
       ;; include-first from a heading's own bol.
       (goto-char (point-min))
       (search-forward "** TODO")
       (let ((recs (jetpacs-org-outline-collect
                    (line-beginning-position) (point-max) t)))
         (should (equal (plist-get (car recs) :title) "Sub")))))))

(ert-deftest jetpacs-org-outline-tree-nests-and-handles-skips ()
  "Nesting follows :level; a skipped level (* -> ***) nests under the
nearest shallower ancestor rather than being dropped."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--outline-fixture
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (org-with-wide-buffer
       (let* ((recs (jetpacs-org-outline-collect (point-min) (point-max) nil))
              (tree (jetpacs-org-outline-tree recs)))
         (should (= 2 (length tree)))
         (should (equal (plist-get (nth 0 tree) :title) "One"))
         (should (equal (plist-get (car (plist-get (nth 0 tree) :children))
                                   :title)
                        "Sub"))
         ;; "Skip" is level 3 directly under level-1 "Two".
         (should (equal (plist-get (car (plist-get (nth 1 tree) :children))
                                   :title)
                        "Skip")))))))

(ert-deftest jetpacs-org-outline-cap-truncates ()
  (let ((jetpacs-org-outline-max-headings 2))
    (should (= 2 (length (jetpacs-org-outline-cap '(a b c d)))))
    (should (equal '(a) (jetpacs-org-outline-cap '(a))))))

(ert-deftest jetpacs-org-file-toplevel-records-root-checked ()
  "Top-level records come back tagged :file/:buffer and only level 1;
a path outside `jetpacs-org-roots' is REFUSED, not read — the poc read
any path handed to it."
  (jetpacs-org-test--with-fixture f jetpacs-org-test--outline-fixture
    (let ((tops (jetpacs-org-file-toplevel-records f)))
      (should (= 2 (length tops)))
      (should (cl-every (lambda (r) (= 1 (plist-get r :level))) tops))
      (should (equal (plist-get (car tops) :file) f))
      (should (stringp (plist-get (car tops) :buffer))))
    ;; Outside the allowlist: refusal, before any read.
    (let ((jetpacs-org-roots (list (make-temp-file "ja5-other" t))))
      (should-error (jetpacs-org-file-toplevel-records f)
                    :type 'jetpacs-org-refused))))

(provide 'jetpacs-org-test)
;;; jetpacs-org-test.el ends here
