;;; jetpacs-keymap-test.el --- JA-3b exit gate: extraction + mining -*- lexical-binding: t; -*-

;;; Commentary:

;; The JA-3 exit-gate halves that live in jetpacs-keymap and
;; jetpacs-commands (docs/PLAN-jetpacs-apps.md JA-3): menu-bar mining
;; over a fixture keymap with :filter/:enable/:visible; binding
;; extraction including the MINOR-MODE map — the poc silently dropped
;; every minor-mode binding by mis-destructuring
;; `current-minor-mode-maps', and the fixture here is the regression
;; witness for that fix; and `jetpacs-command-visible-p' proving a
;; suppressed command is UNREACHABLE from a require-match picker, not
;; merely unsuggested.

;;; Code:

(require 'ert)
(require 'jetpacs-commands)
(require 'jetpacs-keymap)

(defun jetpacs-keymap-test--cmd (name)
  "Intern NAME and make it a distinct command."
  (let ((sym (intern name)))
    (fset sym (lambda () (interactive) sym))
    sym))

;;;; Visibility (JA-3a)

(ert-deftest jetpacs-keymap-visible-p-baseline ()
  ;; Not a command at all (a macro): the commandp baseline refuses it.
  (should-not (jetpacs-command-visible-p 'ignore-errors))
  (should (jetpacs-command-visible-p 'find-file))
  ;; The consolidation entries: keymap noise is now globally suppressed.
  (should-not (jetpacs-command-visible-p 'self-insert-command))
  (should-not (jetpacs-command-visible-p 'keyboard-quit))
  ;; Regexp entries.
  (should-not (jetpacs-command-visible-p 'mouse-set-point)))

(ert-deftest jetpacs-keymap-suppressed-command-is-unreachable ()
  "The picker completes with require-match over `obarray' with
`jetpacs-command-visible-p' as predicate; a suppressed command must
fail `test-completion' — the exact test require-match applies — so it
cannot be run even typed in full."
  (let ((cmd (jetpacs-keymap-test--cmd "jetpacs-keymap-test-suppressed")))
    (unwind-protect
        (progn
          ;; Visible before suppression: reachable.
          (should (test-completion (symbol-name cmd) obarray
                                   #'jetpacs-command-visible-p))
          ;; The definition-site channel.
          (put cmd 'jetpacs-unsupported t)
          (should-not (test-completion (symbol-name cmd) obarray
                                       #'jetpacs-command-visible-p))
          (should-not (all-completions (symbol-name cmd) obarray
                                       #'jetpacs-command-visible-p)))
      (put cmd 'jetpacs-unsupported nil))))

;;;; Binding extraction (JA-3b)

(ert-deftest jetpacs-keymap-extracts-minor-mode-bindings ()
  "THE poc-bug regression: `current-minor-mode-maps' returns plain
keymaps; destructuring them as (VAR . MAP) extracted nothing.  A
binding that exists ONLY in a minor-mode map must be extracted."
  (defvar jetpacs-keymap-test-minor nil)
  (let* ((cmd (jetpacs-keymap-test--cmd "jetpacs-keymap-test-minor-cmd"))
         (mmap (make-sparse-keymap)))
    (define-key mmap (kbd "q") cmd)
    (with-temp-buffer
      (setq-local jetpacs-keymap-test-minor t)
      (let* ((minor-mode-map-alist
              (cons (cons 'jetpacs-keymap-test-minor mmap)
                    minor-mode-map-alist))
             (rows (jetpacs-keymap-extract-bindings (current-buffer)))
             (row (assoc "q" rows)))
        (should row)
        (should (eq (nth 1 row) cmd))
        (should (eq (nth 2 row) 'minor))))))

(ert-deftest jetpacs-keymap-nearer-map-wins-and-noise-drops ()
  "Minor beats local for the same key; suppressed and denylisted
commands never appear; mouse keys never appear."
  (defvar jetpacs-keymap-test-minor2 nil)
  (let* ((minor-cmd (jetpacs-keymap-test--cmd "jetpacs-keymap-test-m1"))
         (local-cmd (jetpacs-keymap-test--cmd "jetpacs-keymap-test-l1"))
         (deny-cmd 'undo)                     ; palette-local denylist
         (mmap (make-sparse-keymap))
         (lmap (make-sparse-keymap)))
    (define-key mmap (kbd "x") minor-cmd)
    (define-key lmap (kbd "x") local-cmd)     ; shadowed by minor
    (define-key lmap (kbd "y") local-cmd)
    (define-key lmap (kbd "z") deny-cmd)
    (define-key lmap [mouse-1] minor-cmd)
    (with-temp-buffer
      (use-local-map lmap)
      (setq-local jetpacs-keymap-test-minor2 t)
      (let* ((minor-mode-map-alist
              (cons (cons 'jetpacs-keymap-test-minor2 mmap)
                    minor-mode-map-alist))
             (rows (jetpacs-keymap-extract-bindings (current-buffer))))
        (should (eq (nth 1 (assoc "x" rows)) minor-cmd))
        (should (eq (nth 1 (assoc "y" rows)) local-cmd))
        (should-not (assoc "z" rows))
        (should-not (seq-find (lambda (r) (string-match-p "mouse" (car r)))
                              rows))))))

;;;; Menu-bar mining (JA-3b — the plan's fixture gate)

(defun jetpacs-keymap-test--menu-fixture ()
  "A local map whose [menu-bar] carries every form the miner handles."
  (let* ((plain (jetpacs-keymap-test--cmd "jetpacs-keymap-test-plain"))
         (hidden (jetpacs-keymap-test--cmd "jetpacs-keymap-test-hidden"))
         (disabled (jetpacs-keymap-test--cmd "jetpacs-keymap-test-disabled"))
         (swapped (jetpacs-keymap-test--cmd "jetpacs-keymap-test-swapped"))
         (legacy (jetpacs-keymap-test--cmd "jetpacs-keymap-test-legacy"))
         (deep (jetpacs-keymap-test--cmd "jetpacs-keymap-test-deep"))
         (menu (make-sparse-keymap "Test"))
         (sub (make-sparse-keymap "Sub"))
         (lmap (make-sparse-keymap)))
    (define-key menu [plain]
                `(menu-item "Plain" ,plain :help "Does the thing\nmore"))
    (define-key menu [hidden]
                `(menu-item "Hidden" ,hidden :visible nil))
    (define-key menu [disabled]
                `(menu-item "Disabled" ,disabled :enable nil))
    (define-key menu [swapped]
                `(menu-item "Swapped" ignore
                            :filter ,(lambda (_real) swapped)))
    (define-key menu [sep] '(menu-item "--"))
    (define-key menu [legacy] (cons "Legacy" legacy))
    (define-key sub [deep] `(menu-item "Deep" ,deep))
    (define-key menu [sub] (cons "Sub" sub))
    (define-key lmap [menu-bar test] (cons "Test" menu))
    lmap))

(ert-deftest jetpacs-keymap-menu-mining-fixture ()
  "The plan's gate: mining over :filter/:enable/:visible/menu-item
forms, breadcrumbs, :help capture, separator and legacy handling."
  (with-temp-buffer
    (use-local-map (jetpacs-keymap-test--menu-fixture))
    (let* ((cands (jetpacs-keymap-menu-candidates (current-buffer)))
           (displays (mapcar #'car cands))
           (cmds (mapcar #'cddr cands)))
      ;; :help's FIRST line rides the display.
      (should (seq-find (lambda (d)
                          (string-match-p "\\`Test ▸ Plain — Does the thing\\'" d))
                        displays))
      ;; :visible nil and :enable nil are gone.
      (should-not (memq (intern "jetpacs-keymap-test-hidden") cmds))
      (should-not (memq (intern "jetpacs-keymap-test-disabled") cmds))
      ;; :filter replaced the real binding.
      (should (memq (intern "jetpacs-keymap-test-swapped") cmds))
      ;; Legacy (STRING . REAL) form parsed.
      (should (memq (intern "jetpacs-keymap-test-legacy") cmds))
      ;; Submenu breadcrumb.
      (should (seq-find (lambda (d) (string-match-p "Test ▸ Sub ▸ Deep" d))
                        displays))
      ;; No separators leaked.
      (should-not (seq-find (lambda (d) (string-prefix-p "--" d))
                            displays)))))

(ert-deftest jetpacs-keymap-mined-menu-honors-suppression ()
  "A menu entry whose command is suppressed does not mine — the same
predicate governs every candidate surface."
  (with-temp-buffer
    (use-local-map (jetpacs-keymap-test--menu-fixture))
    (let ((plain (intern "jetpacs-keymap-test-plain")))
      (unwind-protect
          (progn
            (put plain 'jetpacs-unsupported t)
            (should-not (memq plain
                              (mapcar #'cddr
                                      (jetpacs-keymap-menu-candidates
                                       (current-buffer))))))
        (put plain 'jetpacs-unsupported nil)))))

;;;; Shadowing: label must equal effect (the destructive diff-mode bug)

(ert-deftest jetpacs-keymap-never-labels-a-key-it-does-not-run ()
  "THE invariant: every offered row's key really runs its command in
that buffer.  Checked against stock `diff-mode', whose map nils out
M-q/M-r/M-A/M-R/M-W/M-g to let the global M-<foo> bindings through —
resurrecting those parent bindings offered `M-q · quit-window' for a
key that runs `fill-paragraph', silently reflowing a patch."
  (require 'diff-mode)
  (with-temp-buffer
    (diff-mode)
    (let ((rows (jetpacs-keymap-extract-bindings (current-buffer))))
      ;; Not vacuous: the mode really does offer rows.
      (should (> (length rows) 10))
      (dolist (row rows)
        (let ((desc (nth 0 row)) (cmd (nth 1 row)))
          ;; Labelled command == what the key runs, and it is live.
          (should (eq cmd (key-binding (kbd desc))))
          (should (commandp cmd))))
      ;; And specifically: the unbound keys are not offered at all.
      (dolist (dead '("M-q" "M-r" "M-A" "M-R" "M-W" "M-g"))
        (should-not (assoc dead rows))))))

(ert-deftest jetpacs-keymap-a-nearer-unbind-blocks-a-farther-command ()
  "An explicit nil in a nearer map CLAIMS the key: nothing farther may
be offered under it, even though `map-keymap' hands us the parent's
binding for the same event."
  (let* ((parent (make-sparse-keymap))
         (child (make-sparse-keymap))
         (cmd (jetpacs-keymap-test--cmd "jetpacs-keymap-test-shadowed")))
    (define-key parent (kbd "u") cmd)
    (set-keymap-parent child parent)
    (define-key child (kbd "u") nil)     ; the deliberate unbind
    (with-temp-buffer
      (use-local-map child)
      ;; The unbind lets the GLOBAL binding through — Emacs resolves `u'
      ;; to self-insert-command here, NOT to the parent's command.
      (should-not (eq cmd (key-binding (kbd "u"))))
      ;; So the palette must not offer the parent's command under it.
      (let ((row (assoc "u" (jetpacs-keymap-extract-bindings
                             (current-buffer)))))
        (should-not (and row (eq (nth 1 row) cmd)))))))

(ert-deftest jetpacs-keymap-a-filtered-nearer-binding-still-claims-its-key ()
  "A nearer binding the palette FILTERS OUT (denylisted) must still
block a farther map's row — otherwise the denylist is bypassed and the
row runs the very command the list exists to keep out."
  (let* ((parent (make-sparse-keymap))
         (child (make-sparse-keymap))
         (cmd (jetpacs-keymap-test--cmd "jetpacs-keymap-test-farther")))
    (define-key parent (kbd "n") cmd)
    (set-keymap-parent child parent)
    (define-key child (kbd "n") #'undo)  ; in jetpacs-keymap-denylist
    (with-temp-buffer
      (use-local-map child)
      (let ((rows (jetpacs-keymap-extract-bindings (current-buffer))))
        ;; Neither the denylisted command nor the farther one is offered.
        (should-not (assoc "n" rows))))))

(ert-deftest jetpacs-keymap-a-prefix-map-claims-its-bare-key ()
  "A prefix keymap claims the bare key: a farther map's command must
not be offered under it (the key resolves to a keymap, so the row
would be dead)."
  (let* ((parent (make-sparse-keymap))
         (child (make-sparse-keymap))
         (sub (make-sparse-keymap))
         (cmd (jetpacs-keymap-test--cmd "jetpacs-keymap-test-prefixed"))
         (leaf (jetpacs-keymap-test--cmd "jetpacs-keymap-test-leaf")))
    (define-key parent (kbd "t") cmd)
    (set-keymap-parent child parent)
    (define-key sub (kbd "x") leaf)
    (define-key child (kbd "t") sub)     ; t is now a PREFIX here
    (with-temp-buffer
      (use-local-map child)
      (let ((rows (jetpacs-keymap-extract-bindings (current-buffer))))
        (should-not (assoc "t" rows))
        ;; The leaf under the prefix is still offered.
        (should (assoc "t x" rows))))))

(ert-deftest jetpacs-keymap-palette-candidates-shape ()
  "Key rows lead (with the key · label display), menu rows follow;
targets discriminate (key . DESC) from (command . SYMBOL)."
  (let ((cmd (jetpacs-keymap-test--cmd "jetpacs-keymap-test-pal"))
        (lmap (jetpacs-keymap-test--menu-fixture)))
    (define-key lmap (kbd "p") cmd)
    (with-temp-buffer
      (use-local-map lmap)
      (let* ((cands (jetpacs-keymap-palette-candidates (current-buffer)))
             (key-row (seq-find (lambda (c) (eq (cadr c) 'key)) cands))
             (cmd-row (seq-find (lambda (c) (eq (cadr c) 'command)) cands)))
        (should key-row)
        ;; (key COMMAND . KEY-DESC): the command is what executes.
        (should (eq (car (cddr key-row)) cmd))
        (should (equal (cdr (cddr key-row)) "p"))
        (should (string-match-p "\\`p  ·  " (car key-row)))
        (should cmd-row)
        ;; Key rows come before menu rows.
        (should (< (seq-position cands key-row)
                   (seq-position cands cmd-row)))))))

(provide 'jetpacs-keymap-test)
;;; jetpacs-keymap-test.el ends here
