;;; smoke-comint.el --- JC-3c + Phase A device gate -*- lexical-binding: t; -*-

;; Drives the comint skin against a live Companion with a REAL `M-x shell'.
;; Both comint P1s are smoke-only by nature: D1 crashed the render on every
;; standard REPL name, and D2 wedged the dispatch extent — neither is
;; visible from a fixture with no live process.
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)
(require 'shell)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-comint)

(defvar smoke-c--fails 0)
(defun smoke-c--check (label ok &optional detail)
  (princ (format "%-46s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-c--fails (1+ smoke-c--fails))))

(defvar smoke-c--ready nil)
(defvar smoke-c--sends 0)

;; A REAL M-x shell — the buffer is literally named *shell*, the name that
;; used to take the whole render down (D1).
(defvar smoke-c--buf
  (save-window-excursion
    (let ((explicit-shell-file-name "/bin/sh"))
      (shell "*shell*"))))

(let ((client
       (jetpacs-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme")
        :receipt-file (make-temp-file "smoke-comint-receipts")
        :ready-function (lambda (_c) (setq smoke-c--ready t)))))

  (smoke-c--check "a real *shell* buffer with a live process"
                  (and (buffer-live-p smoke-c--buf)
                       (process-live-p (get-buffer-process smoke-c--buf))))
  (smoke-c--check "the JC-3c skin claims comint-mode"
                  (eq (with-current-buffer smoke-c--buf
                        (seq-some (lambda (c)
                                    (and (derived-mode-p (car c)) (cdr c)))
                                  jetpacs-render-buffer-functions))
                      #'jetpacs-comint-render))
  ;; D1: the render itself. This SIGNALLED before Phase A.
  (smoke-c--check "*shell* renders without signalling (D1)"
                  (condition-case e
                      (and (jetpacs-comint-render smoke-c--buf) t)
                    (error (format "SIGNAL %S" e))))

  (let ((real (gethash "comint.send" jetpacs-action-handlers)))
    (puthash "comint.send"
             (lambda (args params)
               (cl-incf smoke-c--sends)
               (funcall real args params))
             jetpacs-action-handlers))

  (with-jetpacs-owner "comint"
    (jetpacs-shell-define-root
     "comint"
     (lambda () (apply #'jetpacs-column
                       (jetpacs-render-buffer smoke-c--buf)))))

  (let ((deadline (+ (float-time) 20)))
    (while (and (not smoke-c--ready) (< (float-time) deadline))
      (accept-process-output nil 0.1)))
  (smoke-c--check "session reaches READY" smoke-c--ready)

  (when smoke-c--ready
    (with-jetpacs-owner "comint"
      (smoke-c--check "transcript pushed through every gate"
                      (integerp (jetpacs-shell-push))))
    (smoke-c--check "whole-buffer record authorizes comint.send (D4)"
                    (jetpacs-buffer-exposed-buffer-p "*shell*" "comint.send"))
    ;; D2, locally: a send with echoes on must TERMINATE inside the extent.
    (with-current-buffer smoke-c--buf (setq-local comint-process-echoes t))
    (let* ((start (float-time))
           (status (funcall (gethash "comint.send" jetpacs-action-handlers)
                            '(:buffer "*shell*" :value "echo jc3-phase-a")
                            '(:surface "app:comint"))))
      (smoke-c--check "comint.send with echoes on returns (D2)"
                      (and (eq status 'accepted)
                           (< (- (float-time) start) 5))
                      (format "%S in %.2fs" status (- (float-time) start))))
    ;; And a handler that PROMPTS is refused rather than wedging (A1).
    (jetpacs-defaction "smoke.prompter"
      (lambda (_a _p) (read-string "type something: ") 'accepted))
    (let ((start (float-time)))
      (smoke-c--check "a prompting handler is refused, not hung (A1)"
                      (and (eq (jetpacs--dispatch
                                client '(:action "smoke.prompter"
                                         :surface "app:comint")
                                (gethash "smoke.prompter"
                                         jetpacs-action-handlers))
                               'rejected)
                           (< (- (float-time) start) 5))))

    (princ "\n  -- 45s: type into the input row and hit Enter --\n")
    (let ((deadline (+ (float-time) 45)))
      (while (< (float-time) deadline)
        (accept-process-output nil 0.2)))
    (smoke-c--check "a comint.send arrived from the device"
                    (> smoke-c--sends 1)
                    (format "%d send(s)" smoke-c--sends)))

  (ebp-client-close client 'smoke-done))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-c--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-c--fails))
(kill-emacs (if (zerop smoke-c--fails) 0 1))
