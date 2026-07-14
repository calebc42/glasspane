;;; glasspane-demo-test.el --- Tests for glasspane-demo
;;; Code:

(require 'glasspane-test-helpers)

;; ─── Shell ──────────────────────────────────────────────────────────────────

;; ─── Transport ──────────────────────────────────────────────────────────────

;; ─── Toast forwarding ───────────────────────────────────────────────────────

;; ─── Completion bridge ──────────────────────────────────────────────────────

;; ─── Editor sync (v2) ───────────────────────────────────────────────────────

;; ─── Pairing auth ───────────────────────────────────────────────────────────

;; ─── Demo files ─────────────────────────────────────────────────────────────

(ert-deftest glasspane-demo-setup-writes-files ()
  "Setup writes every tour file, non-trivially sized, and is idempotent."
  (let ((dir (make-temp-file "glasspane-demo" t)))
    (unwind-protect
        (progn
          (glasspane-demo-setup dir)
          (glasspane-demo-setup dir)          ; overwrite must not error
          (dolist (f '("demo.el" "demo.py" "demo.sh" "demo.c" "demo.org"))
            (let ((path (expand-file-name f dir)))
              (should (file-exists-p path))
              (should (> (file-attribute-size (file-attributes path)) 200)))))
      (delete-directory dir t))))

(ert-deftest glasspane-demo-el-is-tour-ready ()
  "The elisp tour file exercises the bridge features it claims to.
Its wrong-arity call must reference a function defined in the same
file (so the byte-compiler can flag it), and completion must fire on
the text it tells the user to type."
  (let ((content (cdr (assoc "demo.el" glasspane-demo--files))))
    (should (string-search "(demo-greet \"world\" 'oops)" content))
    (should (string-search "(defun demo-greet (name)" content))
    ;; The completion instruction actually completes.
    (let ((result (jetpacs-complete-in-text "demo.el" "(buffer-sub" 11)))
      (should result)
      (should (equal (car result) "buffer-sub")))))

;; ─── Demo org corpus ─────────────────────────────────────────────────────────

(ert-deftest glasspane-demo-org-corpus-is-valid ()
  "The demo org corpus writes, re-writes, parses, and exercises the
rich renderers (native table, babel run button)."
  (require 'ob-emacs-lisp)
  (let ((dir (make-temp-file "glasspane-demo-org" t)))
    (unwind-protect
        (progn
          (glasspane-demo-setup-org dir)
          (glasspane-demo-setup-org dir)  ; overwrite must not error
          (should (= (length glasspane-demo--org-files) 7))
          (dolist (spec glasspane-demo--org-files)
            (should (glasspane-org-reader-file
                     (expand-file-name (car spec) dir))))
          (should (jetpacs-tests--find-node
                   (glasspane-org-reader-file (expand-file-name "health.org" dir))
                   (lambda (n) (equal (alist-get 't n) "table"))))
          (should (jetpacs-tests--find-node
                   (glasspane-org-reader-file (expand-file-name "notes.org" dir))
                   (lambda (n)
                     (equal (alist-get 'action (alist-get 'on_tap n))
                            "org.babel.execute")))))
      (dolist (spec glasspane-demo--org-files)
        (when-let ((buf (find-buffer-visiting
                         (expand-file-name (car spec) dir))))
          (kill-buffer buf)))
      (delete-directory dir t))))

(ert-deftest glasspane-demo-org-dates-land-relative-to-today ()
  "The corpus's authored dates shift as one block onto the run day:
what was scheduled on the authoring anchor is scheduled today, and the
shifter rewrites every day-named stamp — repeaters and clock ranges
ride along with day names recomputed."
  ;; The pure shifter, deterministically.
  (should (equal (glasspane-demo--shift-timestamps
                  (concat "SCHEDULED: <2026-07-05 Sun +1w>\n"
                          "CLOCK: [2026-07-01 Wed 06:30]--[2026-07-01 Wed 07:15] =>  0:45")
                  3)
                 (concat "SCHEDULED: <2026-07-08 Wed +1w>\n"
                         "CLOCK: [2026-07-04 Sat 06:30]--[2026-07-04 Sat 07:15] =>  0:45")))
  ;; A zero shift (running on the authoring day) is byte-identical.
  (should (equal (glasspane-demo--shift-timestamps "<2026-07-06 Mon>" 0)
                 "<2026-07-06 Mon>"))
  ;; End to end: the written corpus schedules the anchor items today,
  ;; whatever day the suite runs.
  (let ((dir (make-temp-file "glasspane-demo-dates" t)))
    (unwind-protect
        (progn
          (glasspane-demo-setup-org dir)
          (let ((today (let ((system-time-locale "C"))
                         (format-time-string "%Y-%m-%d %a")))
                (all (mapconcat
                      (lambda (spec)
                        (with-temp-buffer
                          (insert-file-contents (expand-file-name (car spec) dir))
                          (buffer-string)))
                      glasspane-demo--org-files "\n")))
            (should (string-search (format "SCHEDULED: <%s>" today) all))))
      (delete-directory dir t))))

(ert-deftest glasspane-demo-link-graph-consistent ()
  "The demo corpus's id links resolve to real :ID: properties, and the
unlinked-mention fixtures ('Babel playground', 'Grace Hopper') appear
as plain text — the on-device backlink checks depend on this graph."
  (let ((ids nil) (targets nil))
    (dolist (entry glasspane-demo--org-files)
      (let ((content (cdr entry)) (pos 0))
        (while (string-match ":ID:[ \t]+\\([0-9a-f-]+\\)" content pos)
          (push (match-string 1 content) ids)
          (setq pos (match-end 0)))
        (setq pos 0)
        (while (string-match "\\[\\[id:\\([0-9a-f-]+\\)\\]" content pos)
          (push (match-string 1 content) targets)
          (setq pos (match-end 0)))))
    (should (>= (length targets) 3))
    (dolist (target targets)
      (should (member target ids))))
  (let ((project (cdr (assoc "project.org" glasspane-demo--org-files)))
        (notes (cdr (assoc "notes.org" glasspane-demo--org-files))))
    ;; Mentions must be plain text, not links.
    (should (string-search "Babel playground over" project))
    (should (string-search "Grace Hopper would" notes))))

(ert-deftest glasspane-demo-srs-registration ()
  "Demo setup registers flashcards.org as review items when org-srs is
around: cards at the card headings, cloze targets wrapped in place,
one items-update per cloze entry.  Without org-srs the file is still
written as plain org."
  (let ((dir (make-temp-file "jetpacs-demo-srs" t))
        (created nil) (clozed nil) (updated 0))
    (unwind-protect
        (progn
          (let ((glasspane-srs--available t))
            (cl-letf (((symbol-function 'org-srs-item-new)
                       (lambda (_type)
                         (push (org-get-heading t t t t) created)))
                      ((symbol-function 'org-srs-item-cloze-default)
                       (lambda (start end &optional _hint)
                         (push (buffer-substring-no-properties start end)
                               clozed)))
                      ((symbol-function 'org-srs-item-cloze-update-entry)
                       (lambda (&optional _) (cl-incf updated))))
              (glasspane-demo-setup-org dir)))
          (should (equal (sort created #'string<)
                         '("Mass–energy equivalence"
                           "What does the Gaussian integral evaluate to?")))
          (should (equal (sort clozed #'string<) '("1947" "a moth")))
          (should (= updated 1))
          ;; Unavailable → written but unregistered, no error.
          (let ((glasspane-srs--available nil))
            (setq created nil)
            (glasspane-demo-setup-org dir)
            (should-not created)
            (should (file-exists-p (expand-file-name "flashcards.org" dir)))))
      (when-let ((buf (find-buffer-visiting
                       (expand-file-name "flashcards.org" dir))))
        (kill-buffer buf))
      (delete-directory dir t))))

(provide 'glasspane-demo-test)
