;;; smoke-theme-mirror.el --- JA-1 device gate: the theme mirror -*- lexical-binding: t; -*-

;; The JA-1 theme exit smoke.  What only hardware can prove: the
;; Companion's overlay+persist path against OUR payload shape (ERT
;; proves the plist, not Compose), the modus.toggle round trip whose
;; visible flip arrives WITHOUT any push call in this script (the
;; enable-theme hook -> debounce -> theme.set ride-along), and the
;; per-client ready-hook re-push that no ERT stub can witness.
;;
;; Phases (driven by the runner):
;;   1. connect in mirror mode under modus-vivendi -> chrome goes dark
;;      with the pushed palette (screenshot)
;;   2. TAP-TOGGLE -> modus.toggle accepted, Emacs flips to operandi,
;;      chrome follows via the hook with no explicit push here
;;   3. mode 'system -> native Material scheme returns (dark omitted)
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-theme)

(defvar smoke-tm--fails 0)
(defun smoke-tm--check (label ok &optional detail)
  (princ (format "%-52s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-tm--fails (1+ smoke-tm--fails))))

(defun smoke-tm--drain (secs &optional stop-fn)
  (let ((deadline (+ (float-time) secs)))
    (while (and (< (float-time) deadline)
                (not (and stop-fn (funcall stop-fn))))
      (accept-process-output nil 0.1))))

(require-theme 'modus-themes)
(load-theme 'modus-vivendi t)
(setq jetpacs-theme-mode 'mirror)

;; A small surface so the screenshot shows themed chrome AND content:
;; badges wear success/warning, the box wears primary_container, and
;; the toggle button drives modus.toggle.
(defun smoke-tm--builder ()
  (jetpacs-column
   (jetpacs-text "JA-1 theme mirror" :style "headline")
   (jetpacs-row (jetpacs-badge "ok" :color "success")
                (jetpacs-badge "warn" :color "warning"))
   (jetpacs-with-attrs
    (jetpacs-box (list (jetpacs-text "container tone" :style "body")))
    :padding 12)
   (jetpacs-button "Toggle" (jetpacs-action "jetpacs.theme.modus-toggle"))))

(with-jetpacs-owner "tm"
  (jetpacs-shell-define-root "tm" #'smoke-tm--builder))

(defvar smoke-tm--ready nil)
(defvar smoke-tm--sent 0)
(advice-add 'ebp-client-theme-set :around
            (lambda (orig &rest args)
              (cl-incf smoke-tm--sent)
              (message "THEME-SET #%d dark=%S colors=%s"
                       smoke-tm--sent (plist-get (cdr args) :dark)
                       (if (plist-get (cdr args) :colors) "yes" "null"))
              (apply orig args)))

(let ((client
       (jetpacs-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme")
        :receipt-file (make-temp-file "smoke-tm-receipts")
        :ready-function (lambda (_c) (setq smoke-tm--ready t)))))

  (smoke-tm--drain 20 (lambda () smoke-tm--ready))
  (smoke-tm--check "session reaches READY" smoke-tm--ready)
  (smoke-tm--check "theme granted" (jetpacs-granted-p "theme"))

  (when smoke-tm--ready
    ;; Phase 1: the ready hook pushed the mirror with NO call here.
    (smoke-tm--drain 3 (lambda () (> smoke-tm--sent 0)))
    (smoke-tm--check "ready hook pushed the mirror (no manual send)"
                     (> smoke-tm--sent 0)
                     (format "%d theme.set" smoke-tm--sent))
    (with-jetpacs-owner "tm" (jetpacs-shell-push "tm"))
    (smoke-tm--drain 3)
    (princ "PHASE1-SCREENSHOT\n") (message "PHASE1-SCREENSHOT")

    ;; Phase 2: the runner taps Toggle; accepted + hook re-push, no
    ;; explicit send in this script.
    (let ((before smoke-tm--sent))
      (smoke-tm--drain 60 (lambda () (eq (jetpacs-modus-current)
                                         'modus-operandi)))
      (smoke-tm--check "modus.toggle flipped the Emacs theme"
                       (eq (jetpacs-modus-current) 'modus-operandi))
      (smoke-tm--drain 5 (lambda () (> smoke-tm--sent before)))
      (smoke-tm--check "the flip re-pushed via the hook alone"
                       (> smoke-tm--sent before)
                       (format "%d -> %d" before smoke-tm--sent)))
    (princ "PHASE2-SCREENSHOT\n") (message "PHASE2-SCREENSHOT")

    ;; Phase 3: back to the native scheme, dark omitted (#36).
    (let ((before smoke-tm--sent))
      (setopt jetpacs-theme-mode 'system)
      (smoke-tm--drain 5 (lambda () (> smoke-tm--sent before)))
      (smoke-tm--check "mode 'system pushed the native clear"
                       (> smoke-tm--sent before)))
    (princ "PHASE3-SCREENSHOT\n") (message "PHASE3-SCREENSHOT")
    (smoke-tm--drain 8))

  (ebp-client-close client 'smoke-done))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-tm--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-tm--fails))
(kill-emacs (if (zerop smoke-tm--fails) 0 1))

;;; smoke-theme-mirror.el ends here
