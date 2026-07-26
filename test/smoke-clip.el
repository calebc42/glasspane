;;; smoke-clip.el --- JA-1 device gate: offline clipboard via builtins -*- lexical-binding: t; -*-

;; The JA-1 clip exit smoke.  THE claim of this rung: a `clipboard.copy'
;; BUILTIN executes device-side from the cached surface, so a copy works
;; with the socket down.  The proof is fully in-band — no cross-app UI:
;; the runner severs the adb forward, taps a copy button, restores the
;; forward, and a SECOND session reads the device clipboard back through
;; the Companion's own `clipboard.read' capability (SPEC 20).  The byte
;; cap is proven on the same read: the 10000-byte entry comes back at
;; exactly its 4096-byte truncation.
;;
;; Phases (runner-driven):
;;   1. push the view; TAP-COPY-A (live) -> clipboard.read equals A
;;   2. SEVER; TAP-COPY-BIG (offline); RESTORE; second session reads the
;;      4096-byte truncation back
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-clip)

(defvar smoke-cl--fails 0)
(defun smoke-cl--check (label ok &optional detail)
  (princ (format "%-52s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-cl--fails (1+ smoke-cl--fails))))

(defun smoke-cl--drain (secs &optional stop-fn)
  (let ((deadline (+ (float-time) secs)))
    (while (and (< (float-time) deadline)
                (not (and stop-fn (funcall stop-fn))))
      (accept-process-output nil 0.1))))

(defconst smoke-cl--a (format "clip-smoke-A-%06d" (random 999999)))
(defconst smoke-cl--big
  (concat "BIGMARK-" (make-string 9992 ?x)))  ; 10000 bytes total

(defun smoke-cl--connect ()
  (jetpacs-connect
   "127.0.0.1" 8765
   :client-name "wsl-emacs" :client-version "30.1"
   :pairing-id "101112131415161718191a1b1c1d1e1f"
   :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
   :wants '("capabilities")
   :receipt-file (make-temp-file "smoke-cl-receipts")))

(defun smoke-cl--clipboard-read ()
  "The device clipboard text via capability.invoke, or the error."
  (let ((got :pending))
    (ebp-client-capability-invoke
     (jetpacs-client) "clipboard.read"
     :callback (lambda (result error)
                 (setq got (if error (list 'err error)
                             (plist-get result :text)))))
    (smoke-cl--drain 10 (lambda () (not (eq got :pending))))
    got))

;; Fixed ring: BIG first (row 2 after the caption), A on top (row 1).
(setq kill-ring (list smoke-cl--a smoke-cl--big "L1\nL2\nL3"))

(let ((client (smoke-cl--connect)))
  (smoke-cl--drain 20 (lambda () (jetpacs-connected-p)))
  (smoke-cl--check "session reaches READY" (jetpacs-connected-p))
  (smoke-cl--check "capabilities granted"
                   (jetpacs-granted-p "capabilities"))

  (when (jetpacs-connected-p)
    (jetpacs-clip-show)
    (smoke-cl--drain 3)
    (princ "PUSHED-TAP-COPY-A\n") (message "PUSHED-TAP-COPY-A")
    ;; Runner taps row A's copy; give it time, then read back.
    (smoke-cl--drain 25)
    (let ((clip (smoke-cl--clipboard-read)))
      (smoke-cl--check "live copy landed on the device clipboard"
                       (equal clip smoke-cl--a)
                       (format "%.24s" (if (stringp clip) clip
                                         (format "%S" clip)))))
    ;; Phase 2: close OUR side entirely — the session is gone but the
    ;; view stays displayed; the runner taps BIG's copy with no Emacs
    ;; anywhere on the wire.  (NOTE deliberately NOT tested: display
    ;; restore after an app cold start — MainActivity's single display
    ;; slot starts blank until the next push, the recorded B18 gap.)
    (ebp-client-close client 'phase2)
    (jetpacs-detach)
    (princ "CLOSED-TAP-BIG\n") (message "CLOSED-TAP-BIG")
    (smoke-cl--drain 40))
  (let ((client2 (ignore-errors (smoke-cl--connect))))
    (smoke-cl--drain 20 (lambda () (jetpacs-connected-p)))
    (smoke-cl--check "second session reaches READY" (jetpacs-connected-p))
    (when (jetpacs-connected-p)
      (let ((clip (smoke-cl--clipboard-read)))
        (smoke-cl--check "offline copy landed (device-side builtin)"
                         (and (stringp clip)
                              (string-prefix-p "BIGMARK-" clip)))
        (smoke-cl--check "byte cap held (exactly 4096 bytes)"
                         (and (stringp clip)
                              (= (string-bytes clip) 4096))
                         (and (stringp clip)
                              (format "%d bytes" (string-bytes clip))))))
    (when client2 (ebp-client-close client2 'smoke-done))))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-cl--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-cl--fails))
(kill-emacs (if (zerop smoke-cl--fails) 0 1))

;;; smoke-clip.el ends here
