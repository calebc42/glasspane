;;; smoke-dialog-prompts.el --- JC-4a device gate -*- lexical-binding: t; -*-

;; The JC-4a exit smoke: real Emacs prompt functions, raised from a real
;; device-originated continuation, answered on the tablet.
;;
;; It drives the WHOLE path the ERT suite can only drive halves of: a
;; device tap -> `jetpacs--dispatch' -> the handler's D2
;; `jetpacs-flow-continue' -> the advised prompt -> a live `dialog.show'
;; -> the user's answer -> the value the prompt returns to its caller.
;; Nothing here stubs `ebp-client-dialog-show'.
;;
;; Phases, selected by EBP_PHASE (each prints markers on stderr for the
;; orchestrator, since batch stdout is block-buffered when redirected):
;;
;;   yn      y-or-n-p             tap Yes            -> t
;;   string  read-string          type + IME Done    -> the text
;;   enum    completing-read      tap an option + OK -> that option
;;   scroll  completing-read over 80 long-labelled options — the JC-4
;;           scroll prerequisite: the LAST option is far below the fold,
;;           so the smoke passes only if the dialog scrolls and that
;;           option is reachable.
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-dialog)

(defconst smoke-dp--phase (or (getenv "EBP_PHASE") "yn"))

(defvar smoke-dp--fails 0)
(defun smoke-dp--check (label ok &optional detail)
  (princ (format "%-52s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-dp--fails (1+ smoke-dp--fails))))

(defvar smoke-dp--ready nil)
(defvar smoke-dp--answer :unset)
(defvar smoke-dp--in-flow nil)
(defvar smoke-dp--flow-surface nil)
(defvar smoke-dp--taps 0)

(defconst smoke-dp--enum-options
  '("alpha" "beta" "gamma" "delta"))

(defconst smoke-dp--scroll-options
  (cl-loop for i from 1 to 80
           collect (format "option-%02d-with-a-long-label-to-force-one-per-row" i))
  "Deliberately long labels AND many of them.
A first attempt used 40 short options and proved nothing: `enum_list'
wraps short chips several to a row, so all 40 fitted on screen and the
dialog never needed to scroll.  Long labels take a row each, so 80 of
them overflow any phone or tablet and the LAST one is only reachable if
the host container scrolls — which is the prerequisite under test.")

(defun smoke-dp--drain (secs &optional stop-fn)
  (let ((deadline (+ (float-time) secs)))
    (while (and (< (float-time) deadline)
                (not (and stop-fn (funcall stop-fn))))
      (accept-process-output nil 0.1))))

(defun smoke-dp--builder ()
  (jetpacs-column
   (jetpacs-text (format "JC-4a prompts — %s" smoke-dp--phase)
                 :style "headline")
   (jetpacs-text (format "answer: %S" smoke-dp--answer) :style "caption")
   (jetpacs-button "ask" (jetpacs-action "dp.ask"))))

;; The handler is the point: it must NOT prompt (D2), it defers through
;; the floor seam, and the prompt runs in that continuation.
(defun smoke-dp--ask ()
  (setq smoke-dp--in-flow (jetpacs-device-flow-p)
        smoke-dp--flow-surface (jetpacs-flow-surface))
  (setq smoke-dp--answer
        (condition-case err
            (pcase smoke-dp--phase
              ("yn" (y-or-n-p "Proceed with the device answer? "))
              ("string" (read-string "Name: "))
              ("enum" (completing-read "Pick one: " smoke-dp--enum-options
                                       nil t))
              ("scroll"
               ;; Above the default threshold on purpose: this phase is
               ;; about the dialog's HEIGHT, so it must stay on the
               ;; enum_list path rather than fall to the text stopgap.
               (let ((jetpacs-dialog-enum-threshold 200))
                 (completing-read "Pick the last: "
                                  smoke-dp--scroll-options nil t)))
              (_ (error "unknown phase")))
          (quit 'quit)
          (error (list 'error (jetpacs--error-label err)))))
  (message "ANSWERED"))

(with-jetpacs-owner "dp"
  (jetpacs-defaction "dp.ask"
                     (lambda (_args _params)
                       (cl-incf smoke-dp--taps)
                       ;; D2: validate now, interact from a continuation.
                       (jetpacs-flow-continue #'smoke-dp--ask)
                       'accepted))
  (jetpacs-shell-define-root "dp" #'smoke-dp--builder))

(let ((client
       (jetpacs-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("surfaces.dialog")
        :receipt-file (make-temp-file "smoke-dp-receipts")
        :ready-function (lambda (_c) (setq smoke-dp--ready t)))))

  (smoke-dp--drain 20 (lambda () smoke-dp--ready))
  (smoke-dp--check "session reaches READY" smoke-dp--ready)
  (smoke-dp--check "dialog profile advertised"
                   (and (plist-get (ebp-client-profiles client) :dialog) t))

  (when smoke-dp--ready
    (with-jetpacs-owner "dp" (jetpacs-shell-push "dp"))
    (smoke-dp--drain 3)
    ;; Marker: the orchestrator taps "ask", which dispatches the handler,
    ;; which defers, which prompts — and the dialog appears.
    (princ "TAP-ASK\n")
    (message "TAP-ASK")
    (smoke-dp--drain 45 (lambda () (not (eq smoke-dp--answer :unset))))

    (smoke-dp--check "the tap dispatched an action" (> smoke-dp--taps 0))
    (smoke-dp--check "the prompt ran inside a device flow"
                     (and smoke-dp--in-flow
                          (equal smoke-dp--flow-surface "app:dp"))
                     (format "flow %S surface %S"
                             smoke-dp--in-flow smoke-dp--flow-surface))
    (smoke-dp--check "the prompt concluded"
                     (not (eq smoke-dp--answer :unset))
                     (format "answer %S" smoke-dp--answer))

    (pcase smoke-dp--phase
      ("yn" (smoke-dp--check "y-or-n-p returned t for a Yes tap"
                             (eq smoke-dp--answer t)
                             (format "%S" smoke-dp--answer)))
      ("string" (smoke-dp--check "read-string returned the typed text"
                                 (equal smoke-dp--answer "devicetext")
                                 (format "%S" smoke-dp--answer)))
      ("enum" (smoke-dp--check "completing-read returned the tapped option"
                               (equal smoke-dp--answer "gamma")
                               (format "%S" smoke-dp--answer)))
      ("scroll"
       (smoke-dp--check "a below-the-fold option was reachable (scroll)"
                        (equal smoke-dp--answer
                               (car (last smoke-dp--scroll-options)))
                        (format "%S" smoke-dp--answer))))

    ;; The answer re-renders the surface: prompts compose with D1 pushes.
    (with-jetpacs-owner "dp" (jetpacs-shell-push "dp"))
    (smoke-dp--drain 3))

  (ebp-client-close client 'smoke-done))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-dp--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-dp--fails))
(kill-emacs (if (zerop smoke-dp--fails) 0 1))

;;; smoke-dialog-prompts.el ends here
