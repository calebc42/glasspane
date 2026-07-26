;;; smoke-picker.el --- JC-4b device gate: the capf picker -*- lexical-binding: t; -*-

;; The JC-4b exit smoke.  A real `completing-read' over a collection too
;; large for the enum fast path, raised from a real device-originated
;; continuation, narrowed by typing ON THE TABLET, and concluded by
;; tapping a candidate.
;;
;; What only hardware can show here: that a dialog-hosted synchronized
;; editor actually renders (the profile change), that keystrokes reach
;; Emacs as §19 deltas, that Emacs's `edit.complete' answers come back
;; as a tappable list, and that tapping one performs a local edit which
;; replaces the completion prefix rather than inserting beside it.
;;
;; Phases (EBP_PHASE):
;;   narrow  type a prefix -> candidates appear -> tap one -> OK
;;   astral  the collection's candidates carry an astral scalar
;;           (U+1D11E), so the prefix arithmetic runs in scalar space on
;;           both sides; a UTF-16 index leaking in lands the splice one
;;           unit off and the picked value comes back malformed.
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-dialog)

(defconst smoke-pk--phase (or (getenv "EBP_PHASE") "narrow"))

(defvar smoke-pk--fails 0)
(defun smoke-pk--check (label ok &optional detail)
  (princ (format "%-52s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-pk--fails (1+ smoke-pk--fails))))

(defconst smoke-pk--collection
  (pcase smoke-pk--phase
    ("astral"
     ;; Astral candidates sharing a plain prefix, so typing ASCII narrows
     ;; to values whose completion arithmetic must be scalar-safe.
     ;;
     ;; PADDED past `jetpacs-dialog-enum-threshold' on purpose. A first
     ;; version listed five candidates and silently took the enum fast
     ;; path instead — the astral value still round-tripped, so the
     ;; phase "passed" without ever exercising the picker. The
     ;; edit.complete counter is what exposed it; keep this list large.
     (append (list "clef-\U0001D11E-alpha" "clef-\U0001D11E-beta"
                   "clef-\U0001D11E-gamma")
             (cl-loop for i from 0 below 60
                      collect (format "filler-%02d" i))))
    (_ (cl-loop for i from 0 below 80 collect (format "cand-%02d" i))))
  "Deliberately over `jetpacs-dialog-enum-threshold' so the PICKER runs,
not the enum fast path.")

(defconst smoke-pk--want
  (pcase smoke-pk--phase
    ("astral" "clef-\U0001D11E-beta")
    (_ "cand-42")))

(defvar smoke-pk--ready nil)
(defvar smoke-pk--answer :unset)
(defvar smoke-pk--in-flow nil)
(defvar smoke-pk--completions 0)

(defun smoke-pk--drain (secs &optional stop-fn)
  (let ((deadline (+ (float-time) secs)))
    (while (and (< (float-time) deadline)
                (not (and stop-fn (funcall stop-fn))))
      (accept-process-output nil 0.1))))

(defun smoke-pk--builder ()
  (jetpacs-column
   (jetpacs-text (format "JC-4b picker — %s" smoke-pk--phase)
                 :style "headline")
   (jetpacs-text (format "answer: %S" smoke-pk--answer) :style "caption")
   (jetpacs-button "ask" (jetpacs-action "pk.ask"))))

(defun smoke-pk--ask ()
  (setq smoke-pk--in-flow (jetpacs-device-flow-p))
  (setq smoke-pk--answer
        (condition-case err
            (completing-read "Pick: " smoke-pk--collection nil t)
          (quit 'quit)
          ;; The full error and a backtrace: a smoke is a diagnostic, and
          ;; `jetpacs--error-label' deliberately drops the datum (SPEC 23.3)
          ;; which is exactly what a failure here needs.
          (error (message "PICKER-ERROR %S\n%s" err
                          (with-output-to-string (backtrace)))
                 (list 'error (jetpacs--error-label err)))))
  (message "ANSWERED"))

(with-jetpacs-owner "pk"
  (jetpacs-defaction "pk.ask"
                     (lambda (_args _params)
                       (jetpacs-flow-continue #'smoke-pk--ask)
                       'accepted))
  (jetpacs-shell-define-root "pk" #'smoke-pk--builder))

;; Count the completion round trips, so the smoke can prove Emacs really
;; answered `edit.complete' rather than the device inventing a list.
(advice-add 'jetpacs-dialog--complete :around
            (lambda (orig &rest args)
              (cl-incf smoke-pk--completions)
              (let ((r (apply orig args)))
                (message "COMPLETE prefix=%S n=%d" (car r) (length (cdr r)))
                r)))

(let ((client
       (jetpacs-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("surfaces.dialog" "editor.sync")
        :receipt-file (make-temp-file "smoke-pk-receipts")
        :ready-function (lambda (_c) (setq smoke-pk--ready t)))))

  (smoke-pk--drain 20 (lambda () smoke-pk--ready))
  (smoke-pk--check "session reaches READY" smoke-pk--ready)
  (smoke-pk--check "editor.sync granted"
                   (and (member "editor.sync"
                                (append (ebp-client-granted client) nil)) t))
  (smoke-pk--check "dialog profile advertises `editor' (JC-4b)"
                   (jetpacs-node-advertised-p "editor" :dialog))
  (smoke-pk--check "the picker path is available"
                   (jetpacs-dialog--picker-available-p))

  (when smoke-pk--ready
    (with-jetpacs-owner "pk" (jetpacs-shell-push "pk"))
    (smoke-pk--drain 3)
    (princ "TAP-ASK\n")
    (message "TAP-ASK")
    (smoke-pk--drain 90 (lambda () (not (eq smoke-pk--answer :unset))))

    (smoke-pk--check "the prompt ran inside a device flow" smoke-pk--in-flow)
    (smoke-pk--check "Emacs answered edit.complete at least once"
                     (> smoke-pk--completions 0)
                     (format "%d completion request(s)" smoke-pk--completions))
    (smoke-pk--check "the picker concluded"
                     (not (eq smoke-pk--answer :unset))
                     (format "answer %S" smoke-pk--answer))
    (smoke-pk--check "completing-read returned the tapped candidate"
                     (equal smoke-pk--answer smoke-pk--want)
                     (format "%S (wanted %S)" smoke-pk--answer smoke-pk--want))

    (with-jetpacs-owner "pk" (jetpacs-shell-push "pk"))
    (smoke-pk--drain 3))

  (ebp-client-close client 'smoke-done))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-pk--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-pk--fails))
(kill-emacs (if (zerop smoke-pk--fails) 0 1))

;;; smoke-picker.el ends here
