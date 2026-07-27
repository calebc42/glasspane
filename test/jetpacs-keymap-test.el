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
        (should (equal (cddr key-row) "p"))
        (should (string-match-p "\\`p  ·  " (car key-row)))
        (should cmd-row)
        ;; Key rows come before menu rows.
        (should (< (seq-position cands key-row)
                   (seq-position cands cmd-row)))))))

(provide 'jetpacs-keymap-test)
;;; jetpacs-keymap-test.el ends here
