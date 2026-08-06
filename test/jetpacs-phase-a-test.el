;;; jetpacs-phase-a-test.el --- Phase A seams + comint P1 exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; Exit gate for the JC-3 review's Phase A cross-file seams and the comint
;; P1s.  Every test here witnesses a specific defect that was LIVE:
;;
;;   A1  jetpacs-with-no-prompts     — a handler could wedge the dispatch
;;                                     extent forever on a local prompt
;;   A2  with-scratch-exposure       — a skin's rewritten taps left the
;;                                     generic verb authorized (SPEC 23.1)
;;   A3  expose-buffer/exposed-p     — buffer-addressing actions had no gate
;;   A4  promoted seams              — five modules on private helpers
;;   D1  comint--input-id            — every standard REPL crashed the render
;;   D2  comint--send-input          — the echo loop pulled a password
;;                                     prompt into the dispatch extent
;;   D3  clear_on_submit             — a failed send ate the user's typing
;;   D4  whole-buffer gate on comint — "a REPL exists" is not "I offered it"

;;; Code:

(require 'ert)
(require 'ebp)
(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-comint)

(defmacro jetpacs-phase-a-test--with-client (&rest body)
  "Attach a stub READY client advertising the Core set, run BODY."
  (declare (indent 0))
  `(let ((client (ebp-client-create
                  :receipt-file (make-temp-file "phase-a-receipts"))))
     (setf (ebp-client-state client) 'ready
           (ebp-client-profiles client)
           '(:app (:node_types ["text" "row" "column" "box" "spacer"
                                "divider" "button" "text_input" "rich_text"]
                   :builtins [] :features [])))
     (unwind-protect
         (progn (jetpacs-attach client) ,@body)
       (jetpacs-detach))))

;; --- A1: the no-prompts seam -------------------------------------------------

(ert-deftest jetpacs-phase-a-no-prompts-closes-every-reader ()
  "Every way of blocking on the local user signals instead.
`inhibit-interaction' alone is NOT enough: the five in
`jetpacs--blocking-readers' ignore it and hang forever, which is why the
macro stubs them too.  A regression here does not fail loudly — it
HANGS, so each is asserted explicitly."
  (dolist (probe (list (cons "read-string"    (lambda () (read-string "x: ")))
                       (cons "read-from-minibuffer"
                             (lambda () (read-from-minibuffer "x: ")))
                       (cons "completing-read"
                             (lambda () (completing-read "x: " '("a"))))
                       (cons "y-or-n-p"       (lambda () (y-or-n-p "x?")))
                       (cons "yes-or-no-p"    (lambda () (yes-or-no-p "x?")))
                       (cons "read-passwd"    (lambda () (read-passwd "p: ")))
                       (cons "read-file-name" (lambda () (read-file-name "f: ")))
                       (cons "read-buffer"    (lambda () (read-buffer "b: ")))
                       (cons "read-number"    (lambda () (read-number "n: ")))
                       (cons "read-char"      (lambda () (read-char)))
                       (cons "read-event"     (lambda () (read-event)))
                       ;; The five that ignore `inhibit-interaction':
                       (cons "read-key-sequence"
                             (lambda () (read-key-sequence "x")))
                       (cons "read-key-sequence-vector"
                             (lambda () (read-key-sequence-vector "x")))
                       (cons "read-key"       (lambda () (read-key "x")))
                       (cons "map-y-or-n-p"
                             (lambda () (map-y-or-n-p "q" #'ignore '(1))))
                       (cons "recursive-edit" (lambda () (recursive-edit)))
                       ;; rmc.el swallows the guard's error and retries in
                       ;; a `while' — a 100% CPU spin `with-timeout' cannot
                       ;; break, because the timer's signal is eaten by the
                       ;; same handler.  If this regresses, the suite BURNS
                       ;; A CORE rather than failing.
                       (cons "read-multiple-choice"
                             (lambda ()
                               (read-multiple-choice "p" '((?a "aa")))))
                       (cons "x-popup-dialog"
                             (lambda () (x-popup-dialog t '("q" ("ok" . t)))))))
    (should (eq 'inhibited-interaction
                (condition-case err
                    (progn (jetpacs-with-no-prompts (funcall (cdr probe)))
                           (format "%s RETURNED without signalling" (car probe)))
                  (error (car err)))))))

(ert-deftest jetpacs-phase-a-no-prompts-refuses-the-gui-dialog-path ()
  "A yes/no prompt must not answer for the user through the GUI path.
`Fyes_or_no_p' (src/fns.c:3546) hands off to `x-popup-dialog' whenever
`use-dialog-box' is on and the last event was a mouse event — a branch
with no `inhibit-interaction' guard.  Verified before the fix: it
RETURNED nil, so a handler silently received \"no\" and proceeded.  A
wrong answer is worse than a hang, because nothing looks broken."
  (let ((use-dialog-box t)
        (last-input-event '(mouse-1))
        (last-nonmenu-event '(mouse-1)))
    (should (eq 'inhibited-interaction
                (condition-case err
                    (progn (jetpacs-with-no-prompts (yes-or-no-p "x?"))
                           'RETURNED-AN-ANSWER)
                  (error (car err)))))))

(ert-deftest jetpacs-phase-a-no-prompts-holds-through-timers ()
  "The ban survives a timer firing INSIDE the extent.
This is the whole reason the seam fixes comint: a process filter defers
`read-passwd' into `run-at-time' 0 precisely so it does not block the
filter, and an `accept-process-output' in the body then pulls it in.  If
timer callbacks ran with the global value, the deferral would be a hole
straight through the macro."
  (let ((seen 'never-ran)
        (proc (start-process "phase-a-sleeper" nil "sleep" "2")))
    (unwind-protect
        (progn
          (run-at-time
           0.1 nil
           (lambda ()
             (setq seen (condition-case err (progn (read-passwd "pw: ") 'RETURNED)
                          (error (car err))))))
          (jetpacs-with-no-prompts
            (let ((deadline (+ (float-time) 1.0)))
              (while (and (eq seen 'never-ran) (< (float-time) deadline))
                (accept-process-output proc 0.05))))
          (should (eq seen 'inhibited-interaction)))
      (delete-process proc))))

(ert-deftest jetpacs-phase-a-dispatch-rejects-a-prompting-handler ()
  "A handler that tries to prompt gets `rejected', not a hung extent.
Answering at all is the point: the Companion is owed a reply, and on a
headless daemon there is nobody to type one."
  (jetpacs-phase-a-test--with-client
    (jetpacs-defaction "phase-a.prompter"
      (lambda (_args _params) (y-or-n-p "may I?") 'accepted))
    (let ((warned nil))
      (cl-letf (((symbol-function 'display-warning)
                 (lambda (&rest _) (setq warned t))))
        (should (eq (jetpacs--dispatch
                     nil '(:action "phase-a.prompter" :surface "app:demo")
                     (gethash "phase-a.prompter" jetpacs-action-handlers))
                    'rejected)))
      ;; Loud on purpose: this is a D2 code bug, not a runtime error.
      (should warned))))

;; --- A2/A3: exposure seams ---------------------------------------------------

(ert-deftest jetpacs-phase-a-scratch-exposure-discards-records ()
  "Records written inside the macro do not survive it (SPEC 23.1)."
  (jetpacs-buffer-forget-exposed)
  (jetpacs-buffer-with-scratch-exposure
    (jetpacs-buffer-expose "*scratch-probe*" 1 "emacs.buffer.act")
    (should (jetpacs-buffer-exposed-p "*scratch-probe*" 1 "emacs.buffer.act")))
  (should-not (jetpacs-buffer-exposed-p "*scratch-probe*" 1 "emacs.buffer.act")))

(ert-deftest jetpacs-phase-a-whole-buffer-records-are-per-verb ()
  "A whole-buffer record authorizes ONE affordance, and cannot be forged
by a position record (or vice versa)."
  (jetpacs-buffer-forget-exposed)
  (jetpacs-buffer-expose-buffer "*wb*" "comint.send")
  (should (jetpacs-buffer-exposed-buffer-p "*wb*" "comint.send"))
  (should-not (jetpacs-buffer-exposed-buffer-p "*wb*" "comint.interrupt"))
  ;; A position record is not a whole-buffer record.
  (jetpacs-buffer-expose "*wb2*" 5 "comint.send")
  (should-not (jetpacs-buffer-exposed-buffer-p "*wb2*" "comint.send"))
  ;; ...and the sentinel key cannot be reached with an integer position.
  (should-not (jetpacs-buffer-exposed-p "*wb*" 0 "comint.send"))
  (jetpacs-buffer-forget-exposed "*wb*")
  (should-not (jetpacs-buffer-exposed-buffer-p "*wb*" "comint.send")))

;; --- A4: the promoted seams --------------------------------------------------

(ert-deftest jetpacs-phase-a-promoted-seams-exist ()
  "The cross-module helpers are public API, and the privates are gone."
  (dolist (fn '(jetpacs-buffer-scalar-text jetpacs-buffer-spans->text
                jetpacs-buffer-node-bytes jetpacs-buffer-cap-spans
                jetpacs-buffer-budgets jetpacs-buffer-defer-refresh
                jetpacs-buffer-line-spans jetpacs-feature-advertised-p
                jetpacs-buffer-expose-buffer jetpacs-buffer-exposed-buffer-p))
    (should (fboundp fn)))
  (should (boundp 'jetpacs-buffer-budget))
  (dolist (gone '(jetpacs-buffer--scalar-text jetpacs-buffer--defer-refresh
                  jetpacs-buffer--node-bytes jetpacs-buffer--cap-spans))
    (should-not (fboundp gone))))

(ert-deftest jetpacs-phase-a-public-line-spans-binds-color-reference ()
  "The public span entry binds the fg/bg reference hexes itself.
Those are bound only inside `jetpacs-buffer--render-region', so a skin
calling in from outside with colors on would find every resolved color
different from nil and stamp an explicit `:color' on EVERY span —
bloating the frame and overriding the device theme.  The failure is
silent, so it is closed in the seam rather than documented."
  (with-temp-buffer
    (insert "plain text\n")
    (rename-buffer "*phase-a-color*" t)
    (let ((jetpacs-buffer-emit-colors t)
          (jetpacs-buffer--default-fg-hex nil)
          (jetpacs-buffer--default-bg-hex nil))
      (let ((spans (jetpacs-buffer-line-spans (point-min) 11 (buffer-name))))
        (should spans)
        ;; Unstyled text must carry NO explicit color.
        (should-not (cl-some (lambda (s) (plist-get s :color)) spans))))))

;; --- D1/D3: the comint input row ---------------------------------------------

(ert-deftest jetpacs-phase-a-comint-input-id-is-valid-for-real-repls ()
  "Every standard REPL name yields a SPEC 4.4 identifier.
The raw name did not, and `jetpacs-text-input' signals on `:id', so the
WHOLE render died on every REPL anyone actually uses."
  (dolist (name '("*shell*" "*ielm*" "*Async Shell Command*"
                  "*inferior-python*" "shell<2>" "*shell*<tramp>"
                  " *hidden*" "«weird»"))
    (let ((id (jetpacs-comint--input-id name)))
      (should (jetpacs-identifier-p id))
      ;; And it builds without signalling.
      (should (jetpacs-text-input id :hint "x"))))
  ;; Sanitizing is lossy, so the hash must keep collisions apart.
  (should-not (equal (jetpacs-comint--input-id "*shell*")
                     (jetpacs-comint--input-id "-shell-")))
  ;; A pathological name still fits the 128-char ceiling.
  (should (jetpacs-identifier-p
           (jetpacs-comint--input-id (make-string 400 ?*)))))

(ert-deftest jetpacs-phase-a-comint-live-render-survives ()
  "A REPL with a LIVE process renders without signalling.
The old ERT could not witness the D1 crash: its fixture had no process,
so no input row was emitted and the assertion checked for the ABSENCE of
the very node that would have signalled."
  (jetpacs-phase-a-test--with-client
    (let ((buf (get-buffer-create "*shell*")))
      (unwind-protect
          (with-current-buffer buf
            (let ((inhibit-read-only t)) (erase-buffer) (insert "$ \n"))
            (comint-mode)
            (let ((proc (start-process "phase-a-cat" buf "cat")))
              (unwind-protect
                  (let* ((nodes (jetpacs-comint-render buf))
                         (json (jetpacs-node->canonical-json (vconcat nodes)))
                         (kinds (jetpacs--collect-node-types
                                 (vconcat nodes) '())))
                    (should (member "text_input" kinds))
                    ;; D3: the field clears via 17.4, not by rotating the id.
                    (should (string-match-p "\"clear_on_submit\":true" json))
                    ;; ...and the id is STABLE across renders (13.6 drafts).
                    (should (equal (jetpacs-comint--input-id "*shell*")
                                   (jetpacs-comint--input-id "*shell*"))))
                (delete-process proc))))
        (kill-buffer buf)))))

;; --- D2/D4: the comint actions -----------------------------------------------

(ert-deftest jetpacs-phase-a-comint-requires-presentation ()
  "SPEC 23.1: a live REPL this Emacs never PRESENTED is refused.
\"A live comint buffer exists\" is not the same claim as \"I offered you
this one\", and only the second is a trust boundary."
  (jetpacs-phase-a-test--with-client
    (let ((buf (get-buffer-create "*shell*"))
          (send (gethash "comint.send" jetpacs-action-handlers)))
      (unwind-protect
          (with-current-buffer buf
            (let ((inhibit-read-only t)) (erase-buffer) (insert "$ \n"))
            (comint-mode)
            (let ((proc (start-process "phase-a-cat2" buf "cat")))
              (unwind-protect
                  (progn
                    (jetpacs-buffer-forget-exposed "*shell*")
                    ;; Live, but never rendered to this Companion.
                    (should (eq (funcall send '(:buffer "*shell*" :value "hi")
                                         '(:surface "app:demo"))
                                'rejected))
                    ;; Rendering is what authorizes it.
                    (jetpacs-comint-render buf)
                    (should (jetpacs-buffer-exposed-buffer-p
                             "*shell*" "comint.send")))
                (delete-process proc))))
        (kill-buffer buf)))))

(ert-deftest jetpacs-phase-a-comint-send-does-not-wedge-on-echo ()
  "D2: `comint.send' completes even with `comint-process-echoes' on.
Unfixed, `comint-send-input' spins in an `accept-process-output' loop
waiting for an echo that never comes — re-entering the jsonrpc filter
from inside the dispatch extent and never returning.  `cat' echoes, but
the assertion that matters is that this TERMINATES: an ERT that hangs is
the regression."
  (jetpacs-phase-a-test--with-client
    (let ((buf (get-buffer-create "*shell*"))
          (send (gethash "comint.send" jetpacs-action-handlers)))
      (unwind-protect
          (with-current-buffer buf
            (let ((inhibit-read-only t)) (erase-buffer))
            (comint-mode)
            (setq-local comint-process-echoes t)   ; gud/prolog/ssh do this
            (let ((proc (start-process "phase-a-cat3" buf "cat")))
              (set-process-query-on-exit-flag proc nil)
              (unwind-protect
                  (progn
                    (jetpacs-comint-render buf)
                    (let ((start (float-time))
                          (status (funcall send '(:buffer "*shell*" :value "hi")
                                           '(:surface "app:demo"))))
                      (should (eq status 'accepted))
                      (should (< (- (float-time) start) 5))))
                (delete-process proc))))
        (kill-buffer buf)))))

(ert-deftest jetpacs-phase-a-comint-send-survives-a-password-prompt ()
  "D2, the sharp end: a process that asks for a password does not wedge.
`comint-watch-for-password-prompt' schedules `read-passwd' through
`run-at-time' 0.  Unfixed, the echo-wait loop's `accept-process-output'
pulls that timer in while the dispatch extent is still on the stack and
Emacs blocks in the minibuffer — forever, on a daemon.  Here the send
must still return a status."
  (jetpacs-phase-a-test--with-client
    (let ((buf (get-buffer-create "*shell*"))
          (send (gethash "comint.send" jetpacs-action-handlers)))
      (unwind-protect
          (with-current-buffer buf
            (let ((inhibit-read-only t)) (erase-buffer))
            (comint-mode)
            (setq-local comint-process-echoes t)
            (let ((proc (start-process "phase-a-pw" buf "cat")))
              (set-process-query-on-exit-flag proc nil)
              (unwind-protect
                  (progn
                    (jetpacs-comint-render buf)
                    ;; Arm the real watcher, then send.
                    (add-hook 'comint-output-filter-functions
                              #'comint-watch-for-password-prompt nil t)
                    (let ((status (funcall send
                                           '(:buffer "*shell*"
                                             :value "Password:")
                                           '(:surface "app:demo"))))
                      (should (memq status '(accepted rejected)))))
                (delete-process proc))))
        (kill-buffer buf)))))

(ert-deftest jetpacs-phase-a-send-input-evaluates-in-ielm ()
  "Bare `comint-send-input' in ielm only ECHOES: the mode's input
sender fills a let-bound `ielm-input' that call never establishes, so
the input lands in a void binding and no evaluation runs (ielm.el,
30.1).  The D2 wrapper must route through `ielm-send-input' — found on
device: the hub's Eval tab echoed forms and never answered."
  (require 'ielm)
  (let ((buf (save-window-excursion (ielm) (current-buffer))))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-max))
          (insert "(+ 40 2)")
          (jetpacs-comint--send-input)
          (should (string-match-p "42" (buffer-string))))
      (when-let* ((p (get-buffer-process buf)))
        (set-process-query-on-exit-flag p nil)
        (delete-process p))
      (kill-buffer buf))))

(provide 'jetpacs-phase-a-test)
;;; jetpacs-phase-a-test.el ends here
