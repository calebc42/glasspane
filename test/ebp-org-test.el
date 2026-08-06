;;; ebp-org-test.el --- JA-4 exit gate: the org engine -*- lexical-binding: t; -*-

;;; Commentary:

;; The JA-4 exit gate (docs/PLAN-jetpacs-apps.md JA-4) plus the biting
;; regressions for the twelve poc defects fixed at the port.  Fixtures
;; are temp .org files (the hypertext-test shape) with
;; `ebp-org-roots' let-bound to the temp directory — resolve-ref's
;; root allowlist refuses everything else by design, so EVERY test that
;; resolves goes through `ebp-org-test--with-fixture'.
;;
;; This process loads NO application layer, and asserts it below.  That
;; is the placement rule for the pure block of run-tests.sh (the
;; ebp-complete precedent), and here it is also the claim under test:
;; the engine earned the `ebp-' prefix by needing nothing above it, so
;; a suite that reached for one jetpacs symbol would be reporting a
;; boundary breach as a passing test.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ebp-org)

(defmacro ebp-org-test--with-no-prompts (&rest body)
  "Run BODY under the floor's D2 no-prompts regime, reproduced HERE.
The dispatch extent binds `inhibit-interaction' and stubs the readers
that ignore it; several tests below pin what the engine's own clamp
does INSIDE that regime — that a would-be question becomes an
`ebp-org-refused' status rather than a raw `inhibited-interaction' or a
hang.  The regime is therefore an INPUT to these tests, and the suite
builds its own: requiring the floor to obtain it would make the engine
suite load the application layer, which is the one thing this file is
not allowed to do.  The reader list mirrors `jetpacs--blocking-readers'
\(jetpacs-surfaces.el), where its per-name justification lives; if that
list grows, this copy is deliberately allowed to lag — it is a fixture,
not a second guard."
  (declare (indent 0) (debug t))
  `(let ((inhibit-interaction t)
         (use-dialog-box nil))
     (cl-letf ,(mapcar
                (lambda (sym)
                  `((symbol-function ',sym)
                    (lambda (&rest _)
                      (signal 'inhibited-interaction
                              (list ,(symbol-name sym))))))
                '(read-key-sequence read-key-sequence-vector read-key
                  map-y-or-n-p recursive-edit read-multiple-choice
                  x-popup-dialog))
       ,@body)))

(ert-deftest ebp-org-suite-loads-no-application-layer ()
  "The engine's own suite must not drag jetpacs in.
`ebp-' is a claim about the require closure, and the delineation guard
proves it for the MODULE.  This proves it for the TEST process, which
is where a convenience require would actually appear: one
`jetpacs-surfaces' for a macro, and the suite would still be green
while the boundary it exists to defend was gone."
  (let ((offenders (cl-remove-if-not
                    (lambda (f) (string-prefix-p "jetpacs" (symbol-name f)))
                    features)))
    (should (equal offenders nil))))

(defmacro ebp-org-test--with-fixture (var content &rest body)
  "Write CONTENT to a temp .org file, bind VAR to its truename, run BODY.
Binds `ebp-org-roots' to the file's directory so resolve-ref admits
it, visits are cleaned up, and engine state is reset around BODY."
  (declare (indent 2))
  `(let* ((,var (file-truename
                 (make-temp-file "ja4-fixture" nil ".org" ,content)))
          (ebp-org-roots (list (file-name-directory ,var))))
     (unwind-protect
         (progn ,@body)
       (when-let* ((buf (find-buffer-visiting ,var)))
         (with-current-buffer buf (set-buffer-modified-p nil))
         (kill-buffer buf))
       (delete-file ,var)
       (ebp-org-reset))))

(defvar ebp-org-test--sexp-ran nil
  "Set by a hostile capture payload if the escape ever fails.")

(defconst ebp-org-test--two-headings
  "* TODO First heading\nBody one.\n* Second heading\n:PROPERTIES:\n:ID: ja4-test-id-1\n:END:\nBody two.\n")

(defun ebp-org-test--ref-to (file headline)
  "A ref plist for HEADLINE in FILE, minted through the real API."
  (with-current-buffer (find-file-noselect file)
    (org-mode)
    (org-with-wide-buffer
     (goto-char (point-min))
     (search-forward headline)
     (ebp-org-ref-at-point))))

;;;; Refs and resolution

(ert-deftest ebp-org-ref-roundtrip-and-float-pos ()
  "A minted ref resolves back to its heading; a float :pos (the JSON
round-trip shape) still takes the trusted-position path."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let ((ref (ebp-org-test--ref-to f "First heading")))
      ;; nth 4 of org-heading-components excludes the TODO keyword.
      (should (equal (plist-get ref :headline) "First heading"))
      (let ((m (ebp-org-resolve-ref ref)))
        (should (markerp m))
        (set-marker m nil))
      ;; Float pos coerces rather than falling to the headline scan.
      (let* ((fref (plist-put (copy-sequence ref) :pos
                              (float (plist-get ref :pos))))
             (m (ebp-org-resolve-ref fref)))
        (should (markerp m))
        (set-marker m nil)))))

(ert-deftest ebp-org-configuration-never-dials-a-remote-name ()
  "JA-4 audit P1-7: the remote guard was applied to the ref's own name but
NOT to the configuration the guard reads.  `org-agenda-files' calls
`file-directory-p' on every raw entry, so one /ssh: entry dialled TRAMP
on every resolve, every mint, and — via the cache stamp — every query,
inside the socket filter against a 60s timeout.  No stat-family
primitive may receive a remote NAME on any of the three hot paths."
  (ebp-org-test--with-fixture f "* TODO H\n"
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
               (ebp-org-roots nil))
          (ebp-org-cache-invalidate)
          (ebp-org--files-stamp)      ; hot path 1: the cache key
          (ebp-org--roots)            ; hot path 2: the allowlist
          (ebp-org--check-file f)     ; hot path 3: every resolve/mint
          (should (null touched)))))))

(ert-deftest ebp-org-check-file-rides-the-floor-guard ()
  "The sandbox itself is shared, not this module's (JA-6 promoted it out);
this module supplies roots and re-signals in its own condition, so a
handler written against the documented status map never sees
`ebp-path-refused'."
  (ebp-org-test--with-fixture f "* H\n"
    (should (equal (ebp-org--check-file f) (file-truename f)))
    (dolist (bad '("relative.org" "/ssh:evil:/x.org" "/etc/passwd"))
      (should (eq 'ebp-org-refused
                  (condition-case err
                      (progn (ebp-org--check-file bad) :no-signal)
                    (ebp-org-refused (car err))
                    (ebp-path-refused (car err))))))
    ;; An unconfigured root set is distinguishable from out-of-policy —
    ;; and RETRYABLE (JA-4 audit P1-10): unmounted storage must never
    ;; delete a durable record.
    (should (eq 'no-roots
                (let ((ebp-org-roots '("/nonexistent-root-xyz")))
                  (condition-case err
                      (progn (ebp-org--check-file f) :no-signal)
                    (ebp-org-unavailable (cadr err))))))))

(ert-deftest ebp-org-file-allowed-p-is-total ()
  "The predicate form NEVER signals — that is its whole reason to exist.
`ebp-org--check-file' splits three conditions apart because a
caller that ANSWERS a request routes each to a different status; a
caller that merely wants to know whether it may READ a path wants one
boolean, and every one of them had written the same wrong
`condition-case' catching `ebp-org-refused' alone.  All three
conditions come back nil here: out of policy (refused), a MISSING file
inside the roots (unresolved — the ordinary missing-image link), and a
collapsed allowlist (unavailable)."
  (ebp-org-test--with-fixture f "* H\n"
    ;; Allowed: the truename, not merely t.
    (should (equal (ebp-org-file-allowed-p f) (file-truename f)))
    ;; Inside the roots but GONE: `ebp-org-unresolved' -> nil.
    (should-not (ebp-org-file-allowed-p
                 (expand-file-name "ja4-never-written.png"
                                   (file-name-directory f))))
    ;; Outside the roots, and not even absolute: `ebp-org-refused'.
    (should-not (ebp-org-file-allowed-p "/etc/passwd"))
    (should-not (ebp-org-file-allowed-p "relative.org"))
    ;; The whole allowlist collapsed: `ebp-org-unavailable' -> nil,
    ;; for a file that is otherwise perfectly readable.
    (let ((ebp-org-roots '("/nonexistent-root-xyz")))
      (should-not (ebp-org-file-allowed-p f)))))

(ert-deftest ebp-org-resolve-refuses-remote-before-any-stat ()
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
      (should (eq 'ebp-org-refused
                  (condition-case err
                      (progn (ebp-org-resolve-ref
                              '(:id nil :file "/ssh:evil:/x.org"
                                :pos 1 :headline "h"))
                             :no-signal)
                    (ebp-org-refused (car err)))))
      (should (= stats 0)))))

(ert-deftest ebp-org-resolve-refuses-outside-roots ()
  "Defect 5: a path outside `ebp-org-roots' is refused, and by path
COMPONENTS — /tmp-evil is not under /tmp."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    ;; Same file, but the allowlist points elsewhere.
    (let ((ebp-org-roots (list (file-truename
                                    (make-temp-file "ja4-other" t)))))
      (should (eq 'ebp-org-refused
                  (condition-case err
                      (progn (ebp-org-resolve-ref
                              (list :id nil :file f :pos 1 :headline ""))
                             :no-signal)
                    (ebp-org-refused (car err))))))))

(ert-deftest ebp-org-resolve-never-triggers-an-org-id-rescan ()
  "Defect 5: the poc's `org-id-find' ran a FULL org-id rescan on a miss.
A bogus :id with a good position must resolve via the position and the
rescan trap must never fire."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (cl-letf (((symbol-function 'org-id-update-id-locations)
               (lambda (&rest _) (error "RESCAN — the org-id-find path"))))
      (let* ((ref (ebp-org-test--ref-to f "First heading"))
             (bogus (plist-put (copy-sequence ref) :id "no-such-id"))
             (m (ebp-org-resolve-ref bogus)))
        (should (markerp m))
        (set-marker m nil)))))

(ert-deftest ebp-org-errors-carry-no-paths ()
  "Defect 12: neither refusal nor unresolved errors embed the path."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (dolist (ref (list (list :id nil :file "/ssh:h:/secret.org"
                             :pos 1 :headline "h")
                       (list :id nil :file f :pos 999999
                             :headline "No Such Heading Anywhere")))
      (let ((err (condition-case e
                     (progn (ebp-org-resolve-ref ref) nil)
                   (error e))))
        (should err)
        (should-not (string-search "secret" (format "%S" err)))
        (should-not (string-search (file-name-nondirectory f)
                                   (format "%S" err)))))))

;;;; Tokens (D-4)

(ert-deftest ebp-org-tokens-are-opaque-and-owner-scoped ()
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let* ((ref (ebp-org-test--ref-to f "First heading"))
           (tokens (ebp-org-ref-tokens (list ref)
                                           :set "s1" :owner "ja4a")))
      (should (= (length tokens) 1))
      ;; No path material in the token string.
      (should-not (string-search (file-name-nondirectory f) (car tokens)))
      ;; Resolves for its owner...
      (should (equal (ebp-org-token-ref (car tokens) :owner "ja4a")
                     ref))
      ;; ...and for nobody else, nor for garbage input.
      (should-not (ebp-org-token-ref (car tokens) :owner "ja4b"))
      (should-not (ebp-org-token-ref 42 :owner "ja4a"))
      (should-not (ebp-org-token-ref "o-forged-1" :owner "ja4a")))))

(ert-deftest ebp-org-token-remint-sweeps-the-old-generation ()
  "The replace-set contract: re-minting a set kills its old tokens —
a swept token is a plain miss the handler answers as `stale'."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let* ((ref (ebp-org-test--ref-to f "First heading"))
           (old (car (ebp-org-ref-tokens (list ref)
                                             :set "s" :owner "ja4")))
           (new (car (ebp-org-ref-tokens (list ref)
                                             :set "s" :owner "ja4"))))
      (should-not (equal old new))
      (should-not (ebp-org-token-ref old :owner "ja4"))
      (should (ebp-org-token-ref new :owner "ja4"))
      ;; Table size stayed = the live set.
      (should (= (hash-table-count ebp-org--tokens) 1)))))

(ert-deftest ebp-org-token-teardown-sweeps-the-owner ()
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let* ((ref (ebp-org-test--ref-to f "First heading"))
           (mine (car (ebp-org-ref-tokens (list ref)
                                              :set "s" :owner "gone")))
           (theirs (car (ebp-org-ref-tokens (list ref)
                                                :set "s" :owner "stays"))))
      (ebp-org-teardown-owner "gone")
      (should-not (ebp-org-token-ref mine :owner "gone"))
      (should (ebp-org-token-ref theirs :owner "stays")))))

(ert-deftest ebp-org-token-mint-validates-refs ()
  "A policy-violating ref signals at MINT time, not at tap time."
  (should-error (ebp-org-ref-tokens
                 (list '(:id nil :file "/ssh:h:/x.org" :pos 1 :headline ""))
                 :set "s" :owner "ja4")
                :type 'ebp-org-refused))

;;;; The cache

(ert-deftest ebp-org-cache-hit-miss-invalidate ()
  "The with-cache gate: one body run, a hit, re-run on invalidate,
re-run on date roll."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let ((runs 0)
          (org-agenda-files (list f)))
      (cl-flet ((probe () (ebp-org-with-cache "ja4t" (list 'k)
                            (cl-incf runs))))
        (probe) (probe)
        (should (= runs 1))
        (ebp-org-cache-invalidate "ja4t")
        (probe)
        (should (= runs 2))
        ;; Date roll busts the key.
        (cl-letf (((symbol-function 'format-time-string)
                   (lambda (&rest _) "2099-01-01")))
          (probe))
        (should (= runs 3))))))

(ert-deftest ebp-org-cache-key-sees-subsecond-and-membership ()
  "Defect 9: full-resolution stamps — two writes inside one float tick
yield distinct keys, and DROPPING a file changes the key even when the
remaining max mtime is unchanged (the poc's max-float was blind to
both)."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let ((g (file-truename
              (make-temp-file "ja4-second" nil ".org" "* Other\n"))))
      (unwind-protect
          (progn
            ;; Distinct sub-second mtimes on the same integer second.
            (set-file-times f (encode-time '(0 0 0 1 1 2026 nil nil 0)))
            (let ((ebp-org--stamp-memo nil)
                  (org-agenda-files (list f)))
              (let ((k1 (ebp-org--cache-key "ns")))
                (set-file-times
                 f (time-add (encode-time '(0 0 0 1 1 2026 nil nil 0))
                             '(0 0 500000 0)))    ; +0.5ms, same second
                (setq ebp-org--stamp-memo nil)
                (let ((k2 (ebp-org--cache-key "ns")))
                  (should-not (equal k1 k2)))))
            ;; Membership: drop a file whose mtime is NOT the max.
            (set-file-times g (encode-time '(0 0 0 1 1 2020 nil nil 0)))
            (let ((ebp-org--stamp-memo nil))
              (let* ((org-agenda-files (list f g))
                     (k-both (ebp-org--cache-key "ns")))
                (setq ebp-org--stamp-memo nil)
                (let* ((org-agenda-files (list f))
                       (k-one (ebp-org--cache-key "ns")))
                  (should-not (equal k-both k-one))))))
        (delete-file g)))))

(ert-deftest ebp-org-cache-stat-memo-bounds-the-sweep ()
  "Defect 9: consecutive lookups within the TTL run ONE stat sweep;
invalidate clears the memo so a mutation is never masked."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let ((stats 0)
          (org-agenda-files (list f))
          (ebp-org--stamp-memo nil))
      (cl-letf* ((real (symbol-function 'file-attributes))
                 ((symbol-function 'file-attributes)
                  (lambda (&rest args) (cl-incf stats) (apply real args))))
        (ebp-org--cache-key "ns")
        (ebp-org--cache-key "ns")
        (should (= stats 1))
        (ebp-org-cache-invalidate)
        (ebp-org--cache-key "ns")
        (should (= stats 2))))))

;;;; Mutations

(ert-deftest ebp-org-with-mutation-escapes-narrowing ()
  "Defect 8: a mutation lands on ITS heading even when the buffer is
narrowed to a different one, and the narrowing survives."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let ((ref (ebp-org-test--ref-to f "Second heading")))
      (with-current-buffer (find-file-noselect f)
        (widen)
        (goto-char (point-min))
        (org-narrow-to-subtree)             ; narrowed to First
        (let ((before (cons (point-min) (point-max))))
          (ebp-org-set-property ref "ja4t" "MOOD" "good")
          (should (equal before (cons (point-min) (point-max)))))
        (org-with-wide-buffer
         (goto-char (point-min))
         (search-forward "Second heading")
         (should (equal (org-entry-get (point) "MOOD") "good")))))))

(ert-deftest ebp-org-toggle-todo-flushes-a-time-note ()
  "Exit-gate half A: under `org-log-done' `time', the toggle writes the
CLOSED stamp inline and leaves NO pending note machinery."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let ((ref (ebp-org-test--ref-to f "First heading"))
          (org-log-done 'time)
          (org-todo-keywords '((sequence "TODO" "DONE"))))
      (ebp-org-toggle-todo ref "ja4t" "DONE")
      (with-current-buffer (find-file-noselect f)
        (org-with-wide-buffer
         (goto-char (point-min))
         (should (search-forward "CLOSED:" nil t))))
      (should-not (bound-and-true-p org-log-setup))
      (should-not (memq 'org-add-log-note post-command-hook)))))

(ert-deftest ebp-org-toggle-todo-never-pops-a-note-buffer ()
  "Defect 2: under `org-log-done' `note' the poc popped a modal
*Org Note* nobody on the device can C-c C-c, and the LOGBOOK line was
never written.  The gate cancels instead: no note buffer, no pending
setup, no hook left armed."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let ((ref (ebp-org-test--ref-to f "First heading"))
          (org-log-done 'note)
          (org-todo-keywords '((sequence "TODO" "DONE")))
          (inhibit-message t))
      (ebp-org-toggle-todo ref "ja4t" "DONE")
      (should-not (get-buffer "*Org Note*"))
      (should-not (bound-and-true-p org-log-setup))
      (should-not (memq 'org-add-log-note post-command-hook))
      ;; The state change itself landed.
      (with-current-buffer (find-file-noselect f)
        (org-with-wide-buffer
         (goto-char (point-min))
         (should (looking-at-p "\\* DONE ")))))))

(ert-deftest ebp-org-set-planning-roundtrip ()
  "The undocumented `org-add-planning-info' idioms this module depends
on, pinned: symbol type to set, trailing remove-arg to clear."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let ((ref (ebp-org-test--ref-to f "First heading")))
      (ebp-org-set-planning ref "ja4t" "SCHEDULED" "<2026-08-01 Sat>")
      (with-current-buffer (find-file-noselect f)
        (org-with-wide-buffer
         (goto-char (point-min))
         (should (search-forward "SCHEDULED: <2026-08-01" nil t))))
      (ebp-org-set-planning ref "ja4t" "SCHEDULED" nil)
      (with-current-buffer (find-file-noselect f)
        (org-with-wide-buffer
         (goto-char (point-min))
         (should-not (search-forward "SCHEDULED:" nil t)))))))

;;;; The deferred save

(ert-deftest ebp-org-defer-save-debounces ()
  "Defect 3: five mutations arm ONE timer, not five."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (with-current-buffer (find-file-noselect f)
      (dotimes (_ 5) (ebp-org-defer-save))
      (should (timerp ebp-org--save-timer))
      ;; Idle timers live on `timer-idle-list', not `timer-list'.
      (should (= 1 (cl-count-if
                    (lambda (tm) (eq (timer--function tm)
                                     #'ebp-org--save-now))
                    timer-idle-list))))))

(ert-deftest ebp-org-defer-save-refuses-superseded-file ()
  "Defect 3: the save body must refuse a superseded file rather than
reach `basic-save-buffer's `yes-or-no-p' — a prompt in a timer wedges a
daemon."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
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
        (ebp-org--save-now buf))
      ;; Refused: still modified, disk content untouched.
      (should (buffer-modified-p buf))
      (with-temp-buffer
        (insert-file-contents f)
        (should (equal (buffer-string) "* Replaced\n")))
      (with-current-buffer buf (set-buffer-modified-p nil)))))

;;;; D2 / file guards (JA-4 audit Batch 3: P1-5, P1-6, relative roots)

(ert-deftest ebp-org-query-skips-a-vanished-agenda-file ()
  "JA-4 audit P1-5: the `agenda' scope marched every configured entry
through `org-check-agenda-file', which MESSAGES the absolute path and
blocks on `read-char-exclusive' when the file is missing.  The query
scope is now the existence-filtered explicit list; an EMPTY set signals
the RETRYABLE `ebp-org-unavailable' with the distinct
`no-agenda-files' data (P1-10) instead of silently scanning whatever
buffer was current (a nil `org-map-entries' scope means exactly that)."
  (ebp-org-test--with-fixture f "* TODO Alive\nbody\n"
    (let ((missing (concat (file-name-directory f) "ja4-vanished.org"))
          (org-directory (file-name-directory f))
          (org-todo-keywords '((sequence "TODO" "|" "DONE")))
          (inhibit-message t))
      (let ((org-agenda-files (list f missing)))
        (should (equal (ebp-org-test--with-no-prompts
                        (ebp-org-query
                         "ja4t" "titles" '(todo "TODO")
                         (lambda () (nth 4 (org-heading-components)))))
                       '("Alive"))))
      (ebp-org-cache-invalidate)
      ;; Nothing left after the filter: a status, never a buffer scan.
      (let* ((org-agenda-files (list missing))
             (err (should-error
                   (ebp-org-test--with-no-prompts
                    (ebp-org-query "ja4t" "titles" '(todo "TODO")
                                       #'ignore))
                   :type 'ebp-org-unavailable)))
        (should (equal (cdr err) '(no-agenda-files)))))))

(ert-deftest ebp-org-resolve-opens-quietly-when-the-file-drifted ()
  "JA-4 audit P1-6, the open sites: with a live buffer whose file
changed on disk, `find-file-noselect' without NOWARN asks whether to
reread — `yes-or-no-p' inside the dispatch extent.  Resolution opens
quietly and answers from the buffer it has."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let ((ref (ebp-org-test--ref-to f "First heading")))
      ;; Drift the disk behind the visiting buffer's back.
      (with-temp-file f (insert ebp-org-test--two-headings "* Late\n"))
      (set-file-times f (time-add (current-time) 2))
      (let ((m (ebp-org-test--with-no-prompts (ebp-org-resolve-ref ref))))
        (should (markerp m))
        (set-marker m nil)))))

(ert-deftest ebp-org-mutation-answers-drift-as-a-status ()
  "JA-4 audit P1-6, supersession: the first buffer modification against
a drifted file raises `ask-user-about-supersession-threat'.  Under the
clamp that is a `ebp-org-refused' STATUS (`file-drifted') the
handler answers `rejected' — not a question, and not a raw
`inhibited-interaction'.  The disk content must genuinely DIFFER: in
30.1 `userlock--check-content-unchanged' silently absorbs a
same-content mtime drift before the threat is ever raised."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let ((ref (ebp-org-test--ref-to f "First heading")))
      (with-temp-file f (insert ebp-org-test--two-headings
                                "* Drifted\n"))
      (set-file-times f (time-add (current-time) 2))
      (let ((err (should-error
                  (ebp-org-test--with-no-prompts
                   (ebp-org-set-property ref "ja4t" "MOOD" "x"))
                  :type 'ebp-org-refused)))
        (should (equal (cdr err) '(file-drifted)))))))

(ert-deftest ebp-org-toggle-todo-refuses-the-catchup-repeater-prompt ()
  "JA-4 audit P1-6, the repeater: `org-auto-repeat-maybe' asks
`y-or-n-p' after ten catch-up shifts of a `++' repeater (emacs-30.1
org.el, nshiftmax).  Under the clamp the toggle refuses as a status
instead of hanging the extent on a question."
  (ebp-org-test--with-fixture f
      (format "* TODO H\nSCHEDULED: <%s ++1d>\n"
              (format-time-string
               "%Y-%m-%d %a"
               (time-subtract (current-time) (days-to-time 30))))
    (let ((ref (ebp-org-test--ref-to f "H"))
          (org-todo-keywords '((sequence "TODO" "|" "DONE")))
          (org-log-done nil)
          (inhibit-message t))
      (let ((err (should-error
                  (ebp-org-test--with-no-prompts
                   (ebp-org-toggle-todo ref "ja4t" "DONE"))
                  :type 'ebp-org-refused)))
        (should (equal (cdr err) '(needs-interactive)))))))

(ert-deftest ebp-org-save-path-never-prompts ()
  "JA-4 audit P1-6, the save arm: `basic-save-buffer' raises
`yes-or-no-p' on a write-protected file; inside the deferred-save timer
that must be a message-refusal — a signal must never escape a timer
body, and a prompt wedges the daemon."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let ((ref (ebp-org-test--ref-to f "First heading"))
          (modes (file-modes f))
          (before (with-temp-buffer (insert-file-contents f)
                                    (buffer-string)))
          (inhibit-message t))
      (unwind-protect
          (progn
            ;; The public mutation arms the ONE deferred-save timer.
            (ebp-org-set-property ref "ja4t" "MOOD" "good")
            (let* ((buf (find-buffer-visiting f))
                   (tm (buffer-local-value 'ebp-org--save-timer buf)))
              (should (timerp tm))
              (set-file-modes f #o444)
              ;; Batch never runs idle timers; fire the body BY HAND.
              (ebp-org-test--with-no-prompts
               (apply (timer--function tm) (timer--args tm)))
              ;; Refused as a message: buffer still modified, disk
              ;; untouched.
              (should (buffer-modified-p buf))
              (should (equal (with-temp-buffer (insert-file-contents f)
                                               (buffer-string))
                             before))))
        (set-file-modes f modes)))))

(ert-deftest ebp-org-relative-root-anchors-to-org-directory ()
  "Batch-3 P2: a relative `ebp-org-roots' or agenda entry anchors
to `org-directory' — matching `org-agenda-files's own expansion — never
to the AMBIENT `default-directory' of whatever buffer the socket
filter happened to have current."
  (ebp-org-test--with-fixture f "* H\n"
    (let* ((fixture-dir (file-name-directory f))
           (decoy (file-name-as-directory
                   (file-truename (make-temp-file "ja4-decoy" t)))))
      (unwind-protect
          (progn
            ;; Anchored: the decoy default-directory must not matter.
            (let ((org-directory fixture-dir)
                  (ebp-org-roots '("."))
                  (default-directory decoy))
              (should (equal (ebp-org--check-file f) f)))
            ;; And the anchor really is org-directory: point it at the
            ;; decoy and the SAME file is refused.
            (let ((org-directory decoy)
                  (ebp-org-roots '("."))
                  (default-directory fixture-dir))
              (should-error (ebp-org--check-file f)
                            :type 'ebp-org-refused))
            ;; Agenda entries expand against org-directory too.
            (let ((org-directory fixture-dir)
                  (org-agenda-files (list (file-name-nondirectory f))))
              (should (equal (ebp-org-agenda-files)
                             (list (concat fixture-dir
                                           (file-name-nondirectory f)))))))
        (delete-directory decoy t)))))

;;;; The token/status contract (JA-4 audit Batch 4: P1-8, P1-9, P1-10)

(ert-deftest ebp-org-token-mint-is-atomic ()
  "JA-4 audit P1-8: the poc swept the old generation and half-installed
the new one BEFORE validating every ref — a failed mint orphaned tokens
past both sweeps (unreachable by replace, by teardown, by the set cap)
and killed the surface's live tokens all at once.  The mint is now
all-or-nothing: a failed mint leaves both tables and the live
generation exactly as they were."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let* ((ref (ebp-org-test--ref-to f "First heading"))
           (bad '(:id nil :file "/ssh:evil:/x.org" :pos 1 :headline ""))
           (old (car (ebp-org-ref-tokens (list ref)
                                             :set "s" :owner "ja4"))))
      (should-error (ebp-org-ref-tokens (list ref bad)
                                            :set "s" :owner "ja4")
                    :type 'ebp-org-refused)
      ;; The failed mint changed NOTHING: the prior generation still
      ;; resolves and no orphan entered the token table.
      (should (equal (ebp-org-token-ref old :owner "ja4") ref))
      (should (= (hash-table-count ebp-org--tokens) 1))
      ;; And teardown still reaches everything.
      (ebp-org-teardown-owner "ja4")
      (should (= (hash-table-count ebp-org--tokens) 0))
      (should-not (ebp-org-token-ref old :owner "ja4")))))

(ert-deftest ebp-org-ambiguous-ref-answers-stale-not-a-guess ()
  "JA-4 audit P1-9 (SPEC 14.5): two identical `* TODO Review' headings,
a token minted for the SECOND, the desktop user edits the first — the
queued tap must answer stale (`ebp-org-unresolved'), never resolve
the first title match and mutate a heading the user did not tap."
  (ebp-org-test--with-fixture f
      (concat "* TODO Review\n" (make-string 200 ?p) "\n"
              "* TODO Review\nbody two\n")
    (let* ((ref (with-current-buffer (find-file-noselect f)
                  (org-mode)
                  (org-with-wide-buffer
                   (goto-char (point-min))
                   (search-forward "* TODO Review")
                   (search-forward "* TODO Review")
                   (ebp-org-ref-at-point))))
           (token (car (ebp-org-ref-tokens (list ref)
                                               :set "s" :owner "ja4")))
           (before (with-temp-buffer (insert-file-contents f)
                                     (buffer-string))))
      ;; The desktop user edits the FIRST heading's body; the ref's
      ;; trusted pos now points past point-max.
      (with-current-buffer (find-file-noselect f)
        (org-with-wide-buffer
         (goto-char (point-min))
         (forward-line 1)
         (delete-region (point) (+ (point) 180))))
      ;; The queued tap: the token still hands back the ref, and the
      ;; mutation answers stale — never a first-match guess.
      (let ((tapped (ebp-org-token-ref token :owner "ja4")))
        (should (equal tapped ref))
        (should-error (ebp-org-set-property tapped "ja4t" "MOOD" "x")
                      :type 'ebp-org-unresolved))
      ;; NEITHER heading was mutated, and nothing reached the disk.
      (with-current-buffer (find-file-noselect f)
        (org-with-wide-buffer
         (goto-char (point-min))
         (should-not (search-forward ":MOOD:" nil t))))
      (should (equal (with-temp-buffer (insert-file-contents f)
                                       (buffer-string))
                     before)))))

(ert-deftest ebp-org-resolve-headline-gate-is-mandatory ()
  "JA-4 audit P1-9 defect (b): an empty :headline is a CLAIM (\"this
heading has no title\" — `ebp-org-ref-at-point' mints \"\" for
those), never a bypass of the trusted-position drift gate."
  (ebp-org-test--with-fixture f "* TODO\nbody\n* TODO Titled\nmore\n"
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (org-with-wide-buffer
       (goto-char (point-min))
       ;; A ref to the TITLE-LESS heading still resolves through pos.
       (let ((bare (ebp-org-ref-at-point)))
         (should (equal (plist-get bare :headline) ""))
         (let ((m (ebp-org-resolve-ref bare)))
           (should (markerp m))
           (should (= (marker-position m) (point-min)))
           (set-marker m nil)))
       ;; A drifted ref: pos points at the TITLED heading but claims no
       ;; title — pre-fix the empty claim OPENED the gate and the wrong
       ;; heading resolved; now it answers stale.
       (search-forward "* TODO Titled")
       (let ((tampered (list :id nil :file f
                             :pos (line-beginning-position)
                             :headline "")))
         (should-error (ebp-org-resolve-ref tampered)
                       :type 'ebp-org-unresolved))))))

(ert-deftest ebp-org-status-split-and-dispositions ()
  "JA-4 audit P1-10: `rejected' means the Companion DELETES the durable
record (SPEC 14.4), so only permanent conditions may map there.
Transient environment goes to `ebp-org-unavailable' (1500
event-retry via `jetpacs-retry-later'); a vanished file is content
drift (`ebp-org-unresolved' -> stale); and
`ebp-org-refusal-disposition' hands handler authors the map."
  (ebp-org-test--with-fixture f "* H\n"
    ;; unreadable on an EXISTING file (an I/O condition) -> unavailable.
    (let ((modes (file-modes f)))
      (unwind-protect
          (progn
            (set-file-modes f 0)
            (let ((err (should-error (ebp-org--check-file f)
                                     :type 'ebp-org-unavailable)))
              (should (equal (cdr err) '(unreadable)))))
        (set-file-modes f modes)))
    ;; An empty EFFECTIVE root set (unmounted storage) -> unavailable.
    (let ((ebp-org-roots (list (concat (file-name-directory f)
                                           "no-such-root/"))))
      (should-error (ebp-org--check-file f)
                    :type 'ebp-org-unavailable))
    ;; A vanished file is content drift -> unresolved (stale).
    (let ((gone (concat (file-name-directory f) "vanished.org")))
      (should-error (ebp-org-resolve-ref
                     (list :id nil :file gone :pos 1 :headline "H"))
                    :type 'ebp-org-unresolved))
    ;; not-absolute / remote / outside-roots stay permanently rejected.
    (dolist (bad (list "relative.org" "/ssh:evil:/x.org"))
      (should-error (ebp-org--check-file bad)
                    :type 'ebp-org-refused))
    (let ((ebp-org-roots (list (file-truename
                                    (make-temp-file "ja4-other" t)))))
      (should-error (ebp-org--check-file f)
                    :type 'ebp-org-refused)))
  ;; The disposition map handler authors get for free.
  (should (eq (ebp-org-refusal-disposition
               '(ebp-org-refused remote))
              'rejected))
  (should (eq (ebp-org-refusal-disposition
               '(ebp-org-unavailable no-roots))
              'retry))
  (should (eq (ebp-org-refusal-disposition
               '(ebp-org-unresolved))
              'stale))
  (should-not (ebp-org-refusal-disposition '(error "x"))))

;;;; Typed extraction

(ert-deftest ebp-org-typed-values ()
  (ebp-org-test--with-fixture f
      "* H\n:PROPERTIES:\n:DONE_BOX: [X]\n:COUNT: 42\n:KIND: b\n:KIND_ALL: a b c\n:BAD: z\n:BAD_ALL: a b c\n:LABELS: x, y z\n:END:\n"
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (org-with-wide-buffer
       (goto-char (point-min))
       (should (eq (ebp-org-entry-typed-value "DONE_BOX" 'checkbox) t))
       (should (= (ebp-org-entry-typed-value "COUNT" 'number) 42))
       (should (equal (ebp-org-entry-typed-value "KIND" 'enum) "b"))
       (should-not (ebp-org-entry-typed-value "BAD" 'enum))
       (should (equal (ebp-org-entry-typed-value "LABELS" 'list)
                      '("x" "y" "z")))
       (should (equal (ebp-org-entry-typed-value "MISSING" 'text) ""))))))

;;;; The query grammar (O2)

(defconst ebp-org-test--agenda
  "* TODO Pay the bill :money:\nSCHEDULED: <2026-08-01 Sat>\nelectric company\n* NEXT Call Alice :work:\n* DONE Old chore :money:\nCLOSED: [2026-07-01 Wed]\n* Plain notes\nnothing actionable\n* TODO [#A] Urgent thing :work:\n"
  "Decoy-laden: every clause below matches SOME entry; only the
conjunction picks exactly one — an accidentally-OR interpreter fails.")

(defmacro ebp-org-test--with-agenda (var &rest body)
  (declare (indent 1))
  `(ebp-org-test--with-fixture ,var ebp-org-test--agenda
     (let ((org-agenda-files (list ,var))
           (org-todo-keywords '((sequence "TODO" "NEXT" "|" "DONE"))))
       ,@body)))

(defun ebp-org-test--titles (tree)
  "Run TREE end-to-end through the REAL entry point; titles returned."
  (ebp-org-query "ja4-test" "titles" tree
                     (lambda () (nth 4 (org-heading-components)))))

(ert-deftest ebp-org-grammar-sexp-conjunction ()
  "Exit gate G1 (sexp): decoys match single clauses; the conjunction
picks exactly one entry."
  (ebp-org-test--with-agenda f
    (should (equal (ebp-org-test--titles
                    (ebp-org-parse-query
                     "(and (todo \"TODO\") (tags \"money\"))"))
                   '("Pay the bill")))
    ;; OR spans; NOT excludes.
    (should (= 2 (length (ebp-org-test--titles
                          (ebp-org-parse-query
                           "(and (todo) (tags \"work\"))")))))
    (should (equal (ebp-org-test--titles
                    (ebp-org-parse-query
                     "(and (tags \"money\") (not (done)))"))
                   '("Pay the bill")))))

(ert-deftest ebp-org-grammar-tokens ()
  "Exit gate G1 (tokens) incl. `priority:' — present in the grammar,
omitted by the plan's gate text."
  (ebp-org-test--with-agenda f
    (should (equal (ebp-org-test--titles
                    (ebp-org-parse-query "todo:TODO tags:work"))
                   '("Urgent thing")))
    (should (equal (ebp-org-test--titles
                    (ebp-org-parse-query "priority:A"))
                   '("Urgent thing")))
    (ebp-org-cache-invalidate)
    (should (equal (ebp-org-test--titles
                    (ebp-org-parse-query "todo:TODO,NEXT tags:work"))
                   '("Call Alice" "Urgent thing")))))

(ert-deftest ebp-org-grammar-freetext ()
  "Exit gate G1 (free text): quoted phrase + bare word, body haystack."
  (ebp-org-test--with-agenda f
    (should (equal (ebp-org-test--titles
                    (ebp-org-parse-query "\"electric company\""))
                   '("Pay the bill")))
    (should (equal (ebp-org-test--titles
                    (ebp-org-parse-query "nothing"))
                   '("Plain notes")))))

(ert-deftest ebp-org-grammar-planning-window ()
  "The :on/:from/:to plist arm over scheduled stamps."
  (ebp-org-test--with-agenda f
    (should (equal (ebp-org-test--titles
                    (ebp-org-parse-query
                     "(scheduled :on \"2026-08-01\")"))
                   '("Pay the bill")))
    (ebp-org-cache-invalidate)
    (should-not (ebp-org-test--titles
                 (ebp-org-parse-query
                  "(scheduled :from \"2026-09-01\")")))))

(ert-deftest ebp-org-query-vet-rejects-hostile-input ()
  "Defect 4 (SPEC 23.2): the rejects family, each through the REAL
`ebp-org-parse-query'."
  (dolist (q '("(delete-file \"/etc/passwd\")"     ; unknown head
               "(todo #[257 \"x\" [] 2])"          ; byte-code object
               "(todo #s(hash-table))"             ; record form
               "(priority > 1.5)"                  ; float
               "(scheduled :evil 1)"               ; stray keyword
               "(and (todo \"A\")) (tags \"b\")"   ; trailing 2nd form
               "'(and #1=(todo \"x\") #1#)"))     ; cycle labels (read-circle nil)
    (should-error (ebp-org-parse-query q) :type 'user-error))
  ;; A #1=-prefixed string never reaches the reader at all: the sexp
  ;; gate requires a leading paren, so it tokenizes into an inert regexp
  ;; query — assert the SAFE routing rather than a refusal.
  (should (eq (car (ebp-org-parse-query "#1=(and . #1#)")) 'and))
  ;; Depth and node caps.
  (should-error (ebp-org-parse-query
                 (concat (make-string 12 ?\() "todo \"x\""
                         (make-string 12 ?\))))
                :type 'user-error)
  (should-error (ebp-org-parse-query
                 (format "(and %s)"
                         (mapconcat (lambda (_) "(todo \"x\")")
                                    (number-sequence 1 100) " ")))
                :type 'user-error))

(ert-deftest ebp-org-query-vet-is-obarray-clean ()
  "Defect 4, the measured half: a hostile query's symbols never reach
the global obarray — even when the query is REFUSED."
  (should-not (intern-soft "ja4-gpzz-never-interned"))
  (condition-case nil
      (ebp-org-parse-query "(and (ja4-gpzz-never-interned 1))")
    (user-error nil))
  (should-not (intern-soft "ja4-gpzz-never-interned"))
  ;; And an ACCEPTED query's argument symbols become strings, not interns.
  (should-not (intern-soft "ja4-gpzz-arg-sym"))
  (should (equal (ebp-org-parse-query "(todo ja4-gpzz-arg-sym)")
                 '(todo "ja4-gpzz-arg-sym")))
  (should-not (intern-soft "ja4-gpzz-arg-sym")))

(ert-deftest ebp-org-query-vet-normalizes-like-the-poc ()
  "Quote unwrapping, literal preservation, bare-symbol stringification."
  (should (equal (ebp-org-parse-query "'(todo TODO)")
                 '(todo "TODO")))
  (should (equal (ebp-org-parse-query "(priority > \"B\")")
                 '(priority > "B")))
  (should (equal (ebp-org-parse-query "(scheduled :from today :to 7)")
                 '(scheduled :from today :to 7)))
  ;; Re-homed heads are the CANONICAL symbols (eq, not just equal).
  (should (eq (car (ebp-org-parse-query "(todo \"X\")")) 'todo)))

(defun ebp-org-test--tree-canonical-p (x)
  "Non-nil when every symbol in tree X is the canonical global intern
and every string carries zero text properties over its whole length."
  (cond
   ((consp x) (and (ebp-org-test--tree-canonical-p (car x))
                   (ebp-org-test--tree-canonical-p (cdr x))))
   ((symbolp x) (eq x (intern-soft (symbol-name x))))
   ((stringp x)
    (cl-loop for i below (length x)
             always (null (text-properties-at i x))))
   (t t)))

(ert-deftest ebp-org-query-vet-refuses-wire-regexp ()
  "JA-4 audit P1-2 (SPEC #137): `regexp' is interpreter vocabulary, not
wire vocabulary — a wire (regexp …) hands the peer a raw regexp engine
\(ReDoS at will).  `heading' regexp-quotes and covers the use case, and
the token arm still mints its own regexp clauses from quoted material."
  (dolist (q '("(regexp \"x\")"
               "(regexp \"\\\\(a*\\\\)*b\")"))
    (let ((err (should-error (ebp-org-parse-query q)
                             :type 'user-error)))
      (should (equal (cadr err) "Unsupported query term"))))
  ;; Positive control: free text still routes through the token arm.
  (should (equal (ebp-org-parse-query "foo") '(regexp "foo"))))

(ert-deftest ebp-org-query-vet-strips-text-properties ()
  "JA-4 audit P1-3: the reader mints PROPERTIZED strings from #(…) wire
text, with throwaway-obarray symbols riding in the property list; the
vetter's output invariant promises fresh propertyless strings, so
enforce it end to end through the public entry point."
  (let ((tree (ebp-org-parse-query
               "(todo #(\"x\" 0 1 (ja4-smug ja4-val)))")))
    (should (equal tree '(todo "x")))
    (should (ebp-org-test--tree-canonical-p tree)))
  ;; Symbols in the output are the canonical global interns.
  (should (ebp-org-test--tree-canonical-p
           (ebp-org-parse-query
            "(and (todo KW) (scheduled :from today))"))))

(ert-deftest ebp-org-parse-query-caps-govern-both-arms ()
  "JA-4 audit P1-4: the caps sat on the sexp arm only — the token arm
had no length bound at all, and the empty quoted phrase minted a
match-everything (regexp \"\") clause."
  ;; Token arm: over-length refuses before tokenizing.
  (let ((err (should-error (ebp-org-parse-query (make-string 201 ?a))
                           :type 'user-error)))
    (should (equal (cadr err) "Query too long")))
  ;; Sexp arm: the SAME cap, before the reader runs.
  (let ((err (should-error
              (ebp-org-parse-query
               (concat "(todo \"" (make-string 200 ?x) "\")"))
              :type 'user-error)))
    (should (equal (cadr err) "Query too long")))
  ;; The empty quoted phrase never mints (regexp "") — nor a bare (and).
  (should-not (ebp-org-parse-query "\"\""))
  (should (equal (ebp-org-parse-query "\"\" x") '(regexp "x")))
  ;; Real depth coverage: nesting ALONE trips the cap (the hostile-input
  ;; test's paren tower dies as a malformed clause before depth counts).
  (let ((err (should-error
              (ebp-org-parse-query
               (concat (apply #'concat (make-list 12 "(not "))
                       "(todo \"x\")"
                       (make-string 12 ?\))))
              :type 'user-error)))
    (should (equal (cadr err) "Query too deep"))))

(ert-deftest ebp-org-query-vet-checks-arity-and-types ()
  "The per-head arity/type schema, and its refusal wording: the head
symbol at most, NEVER the query text (SPEC 23.3)."
  (pcase-dolist (`(,q . ,msg)
                 '(("(done \"x\")"  . "Malformed done clause")
                   ("(not)"         . "Malformed not clause")
                   ("(habit 1)"     . "Malformed habit clause")
                   ("(level \"3\")" . "Malformed level clause")
                   ("(and \"x\")"   . "Malformed query clause")))
    (let ((err (should-error (ebp-org-parse-query q)
                             :type 'user-error)))
      (should (equal (cadr err) msg))))
  (let ((err (should-error
              (ebp-org-parse-query "(level 3 \"SNEAKPAYLOAD\")")
              :type 'user-error)))
    (should (equal (cadr err) "Malformed level clause"))
    (should-not (string-search "SNEAKPAYLOAD" (format "%S" err)))))

(ert-deftest ebp-org-query-vet-refuses-special-properties ()
  "Every `org-special-properties' name is path/derived data with a
dedicated grammar head; (property \"FILE\") would leak absolute paths
through a grammar that promises path-free results."
  (dolist (q '("(property \"FILE\")"
               "(property \"file\")"
               "(property \"TODO\" \"x\")"))
    (let ((err (should-error (ebp-org-parse-query q)
                             :type 'user-error)))
      (should (equal (cadr err) "Unsupported property name"))))
  ;; Ordinary properties still pass, with and without a value.
  (should (equal (ebp-org-parse-query "(property \"MOOD\" \"good\")")
                 '(property "MOOD" "good")))
  (should (equal (ebp-org-parse-query "(property \"MOOD\")")
                 '(property "MOOD"))))

(ert-deftest ebp-org-priority-comparator-inverts ()
  "org urgency runs A > B > C: the comparator flips against the chars."
  (ebp-org-test--with-agenda f
    ;; "higher than B" must return the #A entry.
    (should (equal (ebp-org-test--titles
                    (ebp-org-parse-query "(priority > \"B\")"))
                   '("Urgent thing")))))

;;;; The interpreter as a public seam (C-2)

(ert-deftest ebp-org-matches-p-drives-a-plain-closure-accessor ()
  "The testability claim, cashed: no org buffer, no note index, no
`org-mode' — just a closure over an alist.  GET is the seam and the
grammar is shared, so an out-of-tree arm plugs its own entries in
exactly this way; every tree below is VETTED through the real
`ebp-org-parse-query', which is the contract callers must honor."
  (let* ((entry '((todo . "TODO")
                  (done . nil)
                  (tags "work")
                  (title . "Call Bob")
                  (properties ("KIND" . "call"))))
         (get (lambda (what &rest args)
                (if (eq what 'property)
                    (cdr (assoc (car args) (alist-get 'properties entry)))
                  (alist-get what entry)))))
    ;; The five WHATs this accessor serves, through the public entry.
    (should (ebp-org-matches-p
             (ebp-org-parse-query "(todo \"TODO\")") get))
    (should (ebp-org-matches-p
             (ebp-org-parse-query "(tags \"work\")") get))
    (should (ebp-org-matches-p
             (ebp-org-parse-query "(heading \"Bob\")") get))
    (should (ebp-org-matches-p
             (ebp-org-parse-query "(property \"KIND\" \"call\")") get))
    (should (ebp-org-matches-p
             (ebp-org-parse-query "(not (done))") get))
    ;; The conjunction, and the decoys it must exclude.
    (should (ebp-org-matches-p
             (ebp-org-parse-query
              "(and (todo \"TODO\") (tags \"work\") (not (done)))")
             get))
    (should-not (ebp-org-matches-p
                 (ebp-org-parse-query "(done)") get))
    (should-not (ebp-org-matches-p
                 (ebp-org-parse-query "(tags \"money\")") get))
    (should-not (ebp-org-matches-p
                 (ebp-org-parse-query "(property \"KIND\" \"mail\")") get))
    ;; A question the accessor cannot serve never matches — it does not
    ;; blow up: an arm advertises its coverage, it does not implement all
    ;; ten to be usable.
    (should-not (ebp-org-matches-p
                 (ebp-org-parse-query "(level 1)") get))))

(ert-deftest ebp-org-matches-p-unvetted-head-names-only-the-head ()
  "An unvetted TREE is a programming error, and it says so: a plain
`error' — never `ebp-org-refused', which SPEC 14.4 would make a
PERMANENT verdict against the user's query for a bug in the calling
code — naming the head symbol and NOTHING else.  Query material is
user data (SPEC 23.3), so no leaf of the tree may ride in the message."
  (let* ((err (should-error
               (ebp-org-matches-p '(clocked "JA4SNEAKPAYLOAD") #'ignore)
               :type 'error))
         (msg (error-message-string err)))
    (should (eq (car err) 'error))
    (should (string-search "unsupported clause head" msg))
    (should (string-search "clocked" msg))
    (should-not (string-search "JA4SNEAKPAYLOAD" msg))
    (should-not (string-search "JA4SNEAKPAYLOAD" (format "%S" err))))
  ;; A tree that is not even a clause answers with its TYPE, still no echo.
  (let* ((err (should-error
               (ebp-org-matches-p "JA4SNEAKPAYLOAD" #'ignore)
               :type 'error))
         (msg (error-message-string err)))
    (should (string-search "unsupported clause head" msg))
    (should (string-search "string" msg))
    (should-not (string-search "JA4SNEAKPAYLOAD" msg))))

;;;; Shared primitives (O3)

(ert-deftest ebp-org-ts-extractors ()
  (should (equal (ebp-org-ts-date "<2026-08-01 Sat 14:30 +1w>")
                 "2026-08-01"))
  (should (equal (ebp-org-ts-time "<2026-08-01 Sat 14:30 +1w>")
                 "14:30"))
  (should (equal (ebp-org-ts-repeater "<2026-08-01 Sat .+2d>") ".+2d"))
  ;; Delay cookies deliberately do not match.
  (should-not (ebp-org-ts-repeater "<2026-08-01 Sat -1d>"))
  (should-not (ebp-org-ts-date nil)))

(ert-deftest ebp-org-capture-prompts-schema ()
  "Exit-gate: the ONE extractor (D-5 dedupe) — %? adds Headline,
defaults drop from labels, duplicates collapse."
  (should (equal (ebp-org-capture-prompts
                  "* %^{Title|untitled} %? %^{Title} %^{Tag}")
                 '("Headline" "Title" "Tag")))
  (should (equal (ebp-org-capture-prompts "* plain") '())))

(ert-deftest ebp-org-capture-fill-precedence ()
  "User value > template default > empty; leftover carets stripped.
Wire values are SENTINELS in the returned text (they are installed after
expansion); a template default is the user's own config and is inlined."
  (let* ((pair (ebp-org-capture-fill
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

(ert-deftest ebp-org-capture-values-are-data-not-template ()
  "JA-4 audit P1-1.  A wire value is substituted only AFTER org-capture
has finished expanding, so no peer text can become template source:
`%(sexp)' must not evaluate, `%[PATH]' must not read a file, and a
literal \\=\\1 or & must not act as replacement-template syntax.  The
regression half matters as much: the USER'S OWN template escapes must
still work, or the fix has bought safety by removing the feature."
  (ebp-org-test--with-fixture target "* Inbox\n"
    (let ((secret (expand-file-name "ja4-secret.txt"
                                    (file-name-directory target))))
      (unwind-protect
          (progn
            (with-temp-file secret (insert "TOP-SECRET-PAYLOAD\n"))
            (setq ebp-org-test--sexp-ran nil)
            (let ((org-capture-templates
                   `(("t" "T" entry (file ,target) "* TODO %^{Title}\n%?")
                     ;; The user's own template, exercising org's power.
                     ("u" "U" entry (file ,target)
                      "* TODO %^{Title} :: %(concat \"tmpl\" \"-sexp-ok\")\n%?"))))
              (ebp-org-capture-run
               "t" `(("Title" . "hi %(progn (setq ebp-org-test--sexp-ran t) \"OWNED\")")
                     ("Headline" . "body")))
              (ebp-org-capture-run
               "t" `(("Title" . ,(format "x %%[%s]" secret)) ("Headline" . "b")))
              (ebp-org-capture-run
               "t" '(("Title" . "back\\1slash & amp") ("Headline" . "b")))
              (ebp-org-capture-run
               "t" '(("Title" . "shared") ("Headline" . "b"))
               "shared %(setq ebp-org-test--sexp-ran 'VIA-EXTRA-BODY)")
              (ebp-org-capture-run
               "u" '(("Title" . "legit") ("Headline" . "b"))))
            (let ((text (with-temp-buffer (insert-file-contents target)
                                          (buffer-string))))
              ;; Nothing from the wire ran, in either carrier.
              (should-not ebp-org-test--sexp-ran)
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

(ert-deftest ebp-org-capture-run-refuses-a-prefix-group ()
  "A 2-element entry is a legal PREFIX GROUP, not a template; indexing
`nth' 4 on one signalled wrong-type-argument."
  (let ((org-capture-templates '(("b" "Templates for buying"))))
    (should-error (ebp-org-capture-run "b" nil) :type 'user-error)))

(ert-deftest ebp-org-capture-run-real ()
  "Exit-gate G3: a REAL org-capture run into a temp target — user
values land, no residue, no lingering capture buffer, and the
filled-copy binding holds (defaults would show if the ORIGINAL entry
re-ran its prompts)."
  (ebp-org-test--with-fixture target "* Inbox\n"
    (let ((org-capture-templates
           `(("t" "Task" entry (file+headline ,target "Inbox")
              "* TODO %^{Title|default-title}\n%?"
              :immediate-finish nil))))   ; the defect-1 shape, on purpose
      (ebp-org-capture-run "t" '(("Title" . "user-title")
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

(ert-deftest ebp-org-capture-run-unknown-key-signals ()
  "The poc silently no-opped an unknown key — a capture that vanished."
  (let ((org-capture-templates (list (list "t" "Task" 'entry '(file "/dev/null") "x"))))
    (should-error (ebp-org-capture-run "zz" nil) :type 'user-error)))

(ert-deftest ebp-org-capture-templates-plist-shape ()
  (let ((org-capture-templates
         (list (list "t" "Task" 'entry '(file "x.org") "* %^{Who} %?"))))
    (let ((one (car (ebp-org-capture-templates))))
      (should (equal (plist-get one :key) "t"))
      (should (equal (plist-get one :description) "Task"))
      (should (equal (append (plist-get one :prompts) nil)
                     '("Headline" "Who"))))))

(ert-deftest ebp-org-parse-logbook-shapes ()
  "The five recognisers, in file order."
  (let ((entries (ebp-org-parse-logbook
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

(ert-deftest ebp-org-parse-logbook-clock-continuation ()
  "Defect 7: a continuation under a CLOCK entry (no :content) must not
grow a spurious leading newline off a nil."
  (let ((entries (ebp-org-parse-logbook
                  "CLOCK: [2026-07-27 Mon 09:00]\nstray continuation\n")))
    (should (= (length entries) 1))
    (should (equal (plist-get (car entries) :content)
                   "stray continuation"))))

(ert-deftest ebp-org-logbook-entries-reads-the-drawer ()
  (ebp-org-test--with-fixture f
      "* TODO H\n:LOGBOOK:\n- State \"DONE\" [2026-07-01 Tue]\n:END:\nBody.\n"
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (org-with-wide-buffer
       (let ((entries (ebp-org-logbook-entries (point-min))))
         (should (= (length entries) 1))
         (should (equal (plist-get (car entries) :to) "DONE")))))))

(ert-deftest ebp-org-set-repeater-roundtrip-and-unterminated ()
  "Add, replace, remove — and defect 6: an unterminated timestamp is a
NO-OP, byte-identical buffer, instead of search-failed escaping."
  (ebp-org-test--with-fixture f
      "* TODO H\nSCHEDULED: <2026-08-01 Sat>\n* Broken\nSCHEDULED: <2026-08-01\n"
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (org-with-wide-buffer
       (goto-char (point-min))
       (ebp-org-set-repeater "SCHEDULED" "+1w")
       (should (save-excursion (goto-char (point-min))
                               (search-forward "<2026-08-01 Sat +1w>" nil t)))
       (goto-char (point-min))
       (ebp-org-set-repeater "SCHEDULED" ".+2d")
       (should (save-excursion (goto-char (point-min))
                               (search-forward "<2026-08-01 Sat .+2d>" nil t)))
       (goto-char (point-min))
       (ebp-org-set-repeater "SCHEDULED" nil)
       (should-not (save-excursion (goto-char (point-min))
                                   (search-forward "+2d" nil t)))
       ;; The unterminated heading: no signal, no change.
       (search-forward "* Broken")
       (let ((before (buffer-string)))
         (ebp-org-set-repeater "SCHEDULED" "+1w")
         (should (equal (buffer-string) before))))
      (set-buffer-modified-p nil))))

(ert-deftest ebp-org-tblfm-field-over-column ()
  "Field formulas (@R$C) beat column formulas ($C), mirroring org."
  (ebp-org-test--with-fixture f
      "| a | b |\n|---+---|\n| 1 | 2 |\n| 3 | 4 |\n#+TBLFM: @3$2=@3$1*2::$2=$1+1\n"
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (org-with-wide-buffer
       (goto-char (point-min))
       (search-forward "| 3 | 4")
       (backward-char 1)
       (should (equal (car (ebp-org-table-field-formula)) "@3$2"))
       (goto-char (point-min))
       (search-forward "| 1 | 2")
       (backward-char 1)
       (should (equal (car (ebp-org-table-field-formula)) "$2"))))))

(ert-deftest ebp-org-format-clock-time-shapes ()
  (should (equal (ebp-org-format-clock-time
                  "2026-07-01 Wed 10:00" "2026-07-01 Wed 11:30")
                 "2026-07-01, 10:00 to 11:30"))
  (should (equal (ebp-org-format-clock-time
                  "2026-07-01 Wed 23:30" "2026-07-02 Thu 00:15")
                 "2026-07-01 23:30 to 2026-07-02 00:15"))
  ;; The degraded arm never signals.
  (should (stringp (ebp-org-format-clock-time "x" "y"))))

;;;; The outline model (JA-5a, amendment A3)

(defconst ebp-org-test--outline-fixture
  (concat "* One\nBody.\n"
          "** TODO [#A] Sub :tag:\nDEADLINE: <2026-01-01 Thu>\nSub body.\n"
          "* DONE Two\n"
          "*** Skip\n")
  "Two roots, a decorated child, and a SKIPPED level under Two.")

(ert-deftest ebp-org-outline-collect-records-fields ()
  "Collection walks every heading; records carry the decoded fields.
`include-first' picks up a heading sitting exactly at BEG."
  (ebp-org-test--with-fixture f ebp-org-test--outline-fixture
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (org-with-wide-buffer
       (let ((recs (ebp-org-outline-collect (point-min) (point-max) nil)))
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
       (let ((recs (ebp-org-outline-collect
                    (line-beginning-position) (point-max) t)))
         (should (equal (plist-get (car recs) :title) "Sub")))))))

(ert-deftest ebp-org-outline-tree-nests-and-handles-skips ()
  "Nesting follows :level; a skipped level (* -> ***) nests under the
nearest shallower ancestor rather than being dropped."
  (ebp-org-test--with-fixture f ebp-org-test--outline-fixture
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (org-with-wide-buffer
       (let* ((recs (ebp-org-outline-collect (point-min) (point-max) nil))
              (tree (ebp-org-outline-tree recs)))
         (should (= 2 (length tree)))
         (should (equal (plist-get (nth 0 tree) :title) "One"))
         (should (equal (plist-get (car (plist-get (nth 0 tree) :children))
                                   :title)
                        "Sub"))
         ;; "Skip" is level 3 directly under level-1 "Two".
         (should (equal (plist-get (car (plist-get (nth 1 tree) :children))
                                   :title)
                        "Skip")))))))

(ert-deftest ebp-org-outline-cap-truncates ()
  (let ((ebp-org-outline-max-headings 2))
    (should (= 2 (length (ebp-org-outline-cap '(a b c d)))))
    (should (equal '(a) (ebp-org-outline-cap '(a))))))

(ert-deftest ebp-org-file-toplevel-records-root-checked ()
  "Top-level records come back tagged :file/:buffer and only level 1;
a path outside `ebp-org-roots' is REFUSED, not read — the poc read
any path handed to it."
  (ebp-org-test--with-fixture f ebp-org-test--outline-fixture
    (let ((tops (ebp-org-file-toplevel-records f)))
      (should (= 2 (length tops)))
      (should (cl-every (lambda (r) (= 1 (plist-get r :level))) tops))
      (should (equal (plist-get (car tops) :file) f))
      (should (stringp (plist-get (car tops) :buffer))))
    ;; Outside the allowlist: refusal, before any read.
    (let ((ebp-org-roots (list (make-temp-file "ja5-other" t))))
      (should-error (ebp-org-file-toplevel-records f)
                    :type 'ebp-org-refused))))

;;;; The cache (JA-4 audit Batch 5: P1-11, P1-12, eviction)

(ert-deftest ebp-org-cache-sees-an-unsaved-buffer-edit ()
  "JA-4 audit P1-11: freshness was derived entirely from the DISK
mtime while EVERY cached value is produced by `org-map-entries' reading
the BUFFER.  An org buffer edited in Emacs and not yet written — the
normal state of a working buffer, and precisely the state
`ebp-org-with-mutation' deliberately leaves for the debounce
window — did not move the key at all, so the phone re-rendered from
positions that no longer exist and a tap then mutated the WRONG
heading.  The stamp now carries `buffer-chars-modified-tick' for every
visiting buffer."
  (ebp-org-test--with-fixture f "* TODO Alpha\n"
    (let ((org-agenda-files (list f))
          (org-todo-keywords '((sequence "TODO" "|" "DONE"))))
      ;; Open the file FIRST: the buffer SET is then identical across
      ;; both queries, so only the edit itself can move the stamp.
      (find-file-noselect f)
      (cl-flet ((titles ()
                  (ebp-org-query
                   "ja4t" "titles" '(todo "TODO")
                   (lambda () (nth 4 (org-heading-components))))))
        (should (equal (titles) '("Alpha")))
        (with-current-buffer (find-buffer-visiting f)
          (org-with-wide-buffer
           (goto-char (point-max))
           (insert "* TODO Beta\n")))
        ;; Nothing reached the disk — the mtime cannot have moved...
        (should (equal (with-temp-buffer
                         (insert-file-contents f) (buffer-string))
                       "* TODO Alpha\n"))
        ;; ...and the repeated query still sees the edit.
        (should (equal (titles) '("Alpha" "Beta")))))))

(ert-deftest ebp-org-query-keys-on-the-caller-supplied-key ()
  "JA-4 audit P1-12: the key was (date, stamp, namespace, tree) while
the cached VALUE is `(mapcar ACTION matches)', so a second caller with
the same tree and a DIFFERENT action silently received the first
caller's payload.  That is a D-4 breach, not merely a cache bug: JA-5
asks one tree for display titles and for refs, and whichever ran
second got the other list — ref plists (absolute paths) to a text
consumer, bare strings to `ebp-org-ref-tokens', whose per-ref
policy check `(plist-get \"Alpha\" :file)' then skipped silently.  KEY
is now mandatory and enters the cache key above the tree."
  (ebp-org-test--with-fixture f "* TODO Alpha\n"
    (let ((org-agenda-files (list f))
          (org-todo-keywords '((sequence "TODO" "|" "DONE")))
          (tree '(todo "TODO")))
      (find-file-noselect f)            ; stable buffer set across all three
      (let ((titles (ebp-org-query
                     "ja4t" "titles" tree
                     (lambda () (nth 4 (org-heading-components)))))
            (refs (ebp-org-query "ja4t" "refs" tree
                                     #'ebp-org-ref-at-point)))
        (should (equal titles '("Alpha")))
        (should (plistp (car refs)))
        (should (equal (plist-get (car refs) :headline) "Alpha"))
        ;; ...and the memo still MEMOISES: the same key hits, so the
        ;; #'ignore action never runs.
        (should (equal (ebp-org-query "ja4t" "titles" tree #'ignore)
                       '("Alpha"))))
      ;; A key is not optional — the whole point is that it cannot be
      ;; forgotten into a collision.
      (should-error (ebp-org-query "ja4t" nil tree #'ignore)))))

(ert-deftest ebp-org-query-key-ignores-print-length ()
  "JA-4 audit P1-12, the printer half: the tree entered the key through
`format \"%S\"', which honours `print-length'/`print-level' — a caller
with either bound collided two DIFFERENT trees onto one entry.  The
serialisation now switches truncation off explicitly."
  (ebp-org-test--with-agenda f
    (find-file-noselect f)
    (let ((print-length 2) (print-level 2))
      (cl-flet ((run (tree)
                  (ebp-org-query
                   "ja4t" "titles" tree
                   (lambda () (nth 4 (org-heading-components))))))
        ;; Truncated to `print-length' 2 both trees print identically.
        (should (equal (run '(and (todo "TODO") (tags "money")))
                       '("Pay the bill")))
        (should (equal (run '(and (todo "TODO") (tags "work")))
                       '("Urgent thing")))))))

(ert-deftest ebp-org-ref-tokens-refuses-a-non-plist-ref ()
  "JA-4 audit P1-12, the downstream half: `(plist-get \"Alpha\" :file)'
returns nil rather than signalling, so a list of DISPLAY STRINGS handed
to the mint (exactly what the missing action key delivered) sailed past
the per-ref policy check and became live tokens.  A ref that is not a
plist carrying :file is now an error — and the offending value is NOT
echoed (23.3)."
  (ebp-org-test--with-fixture f ebp-org-test--two-headings
    (let ((ref (ebp-org-test--ref-to f "First heading")))
      (let ((err (should-error
                  (ebp-org-ref-tokens '("First heading" "Second heading")
                                          :set "s" :owner "ja4"))))
        (should-not (string-search "First heading" (format "%S" err))))
      ;; A plist that is not a REF (no :file) is refused too: its
      ;; policy check would silently be a no-op.
      (should-error (ebp-org-ref-tokens
                     (list '(:id nil :pos 1 :headline "x"))
                     :set "s" :owner "ja4"))
      ;; Nothing was minted by either attempt, and a real ref still mints.
      (should (= (hash-table-count ebp-org--tokens) 0))
      (should (= 1 (length (ebp-org-ref-tokens
                            (list ref) :set "s" :owner "ja4")))))))

(ert-deftest ebp-org-cache-evicts-instead-of-growing ()
  "JA-4 audit P2 (Cache): every distinct stamp minted a NEW key
generation and nothing ever evicted, while the key embeds wire-supplied
query text — N hostile queries retained N entries for the process
lifetime.  A stamp change now drops the superseded generation
wholesale, and the live generation is capped."
  (ebp-org-test--with-fixture f "* TODO Alpha\n"
    (let ((org-agenda-files (list f)))
      (find-file-noselect f)
      (ebp-org-cache-invalidate)     ; a known-empty starting table
      (should (= 1 (ebp-org-with-cache "ja4t" (list 'k) 1)))
      (should (= 1 (hash-table-count ebp-org--cache)))
      ;; An unsaved buffer edit moves the stamp (P1-11), so this is a
      ;; new generation: the body re-runs AND the old entry is gone.
      (with-current-buffer (find-buffer-visiting f)
        (org-with-wide-buffer
         (goto-char (point-max))
         (insert "* TODO Beta\n")))
      (should (= 2 (ebp-org-with-cache "ja4t" (list 'k) 2)))
      (should (= 1 (hash-table-count ebp-org--cache)))
      ;; The LIVE generation is bounded too.
      (dotimes (i (* 2 ebp-org-cache-max))
        (ebp-org-with-cache "ja4t" (list 'k i) i))
      (should (<= (hash-table-count ebp-org--cache)
                  ebp-org-cache-max)))))

(provide 'ebp-org-test)
;;; ebp-org-test.el ends here
