;;; smoke-floor.el --- JC-0/JC-1 device gate -*- lexical-binding: t; -*-

;; The exit-gate smoke deferred from JC-0 and JC-1: drives the whole new
;; application layer against a live Companion.
;;
;;   jetpacs-connect      -> ebp-connect + attach + the state/barrier seams
;;   jetpacs-defaction    -> the SPEC 14 shim, replayed into the client
;;   jetpacs-shell-define-root / -push  -> the four runtime gates
;;   jetpacs-buffer-render -> the Tier-0 renderer over a REAL Emacs buffer
;;   emacs.buffer.act     -> a tap, exposure-validated, effect synchronous
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765`.  Prints a
;; PASS/FAIL line per check and exits non-zero on any failure.

(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)

(defvar smoke-floor--fails 0)
(defun smoke-floor--check (label ok &optional detail)
  (princ (format "%-46s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-floor--fails (1+ smoke-floor--fails))))

;; A real Emacs buffer with fontification, a button, and a TAB — the
;; Tier-0 renderer's actual job.
(defvar smoke-floor--buffer
  (with-current-buffer (get-buffer-create "*smoke-floor-src*")
    (erase-buffer)
    (insert "JC-0/JC-1 device smoke\n")
    (insert (concat (propertize "bold" 'face '(:weight bold))
                    "  "
                    (propertize "red" 'face '(:foreground "red"))
                    "  plain\n"))
    (insert "col1\tcol2\n")
    (insert-text-button "TAP ME" 'action
                        (lambda (_) (setq smoke-floor--tapped t)))
    (insert "\n")
    (current-buffer)))

(defvar smoke-floor--tapped nil)
(defvar smoke-floor--pushed nil)
(defvar smoke-floor--ready nil)

(let ((client
       (jetpacs-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme")
        :receipt-file (make-temp-file "smoke-floor-receipts")
        :ready-function (lambda (_c) (setq smoke-floor--ready t)))))

  ;; The floor's own registration path, inside an owner scope (decision D1:
  ;; this owner names the surface app:smoke).
  (with-jetpacs-owner "smoke"
    (jetpacs-defaction "smoke.ping"
                       (lambda (args _params)
                         (princ (format "  ping args=%S\n" args))
                         'accepted))
    (jetpacs-shell-define-root
     "smoke"
     (lambda ()
       (jetpacs-column
        (jetpacs-text "JC-0 floor + JC-1 renderer" :style "headline")
        (jetpacs-text (format "tapped: %s" (if smoke-floor--tapped "YES" "no"))
                      :style "caption")
        (jetpacs-button "ping" (jetpacs-action "smoke.ping"
                                               :args '(:from "device")))
        (jetpacs-divider)
        ;; The Tier-0 renderer's output, spliced straight in.
        (apply #'jetpacs-column
               (jetpacs-buffer-render smoke-floor--buffer))))))

  ;; Wait for READY (the welcome + 10.3 barrier), then push.
  (let ((deadline (+ (float-time) 20)))
    (while (and (not smoke-floor--ready) (< (float-time) deadline))
      (accept-process-output nil 0.1)))
  (smoke-floor--check "session reaches READY" smoke-floor--ready)
  (smoke-floor--check "jetpacs-connected-p" (jetpacs-connected-p))
  (smoke-floor--check "attach replayed the action into the client"
                      (and (gethash "smoke.ping" (ebp-client-actions client))
                           t))
  (smoke-floor--check "view.switched is allowlisted (14.2/24.2)"
                      (and (gethash "view.switched"
                                    (ebp-client-actions client))
                           t))

  (when smoke-floor--ready
    ;; The push: builds through jetpacs-shell--build, clears all four
    ;; gates against the LIVE welcome profile, and sends.
    (with-jetpacs-owner "smoke"
      (setq smoke-floor--pushed (jetpacs-shell-push)))
    (smoke-floor--check "jetpacs-shell-push claimed a revision"
                        (integerp smoke-floor--pushed)
                        (format "revision %s" smoke-floor--pushed))
    (smoke-floor--check "pushed to the D1 per-owner surface"
                        (gethash "app:smoke" (ebp-client-revisions client))
                        "app:smoke")

    ;; Report what the live welcome actually advertises — the gates run
    ;; against this, and the audit flagged max_rich_spans as missing.
    (let* ((profile (plist-get (ebp-client-profiles client) :app))
           (limits (ebp-client-limits client)))
      (princ (format "  app node_types: %d, builtins: %d, features: %S\n"
                     (length (plist-get profile :node_types))
                     (length (plist-get profile :builtins))
                     (append (plist-get profile :features) nil)))
      (princ (format "  max_rich_spans=%S  max_frame_bytes=%S\n"
                     (plist-get limits :max_rich_spans)
                     (plist-get limits :max_frame_bytes)))
      (smoke-floor--check "rich_text advertised (else Core-text fallback)"
                          (and (member "rich_text"
                                       (append (plist-get profile :node_types)
                                               nil))
                               t)))

    ;; Hold the session open so a human (or adb) can tap.
    (princ "\n  -- 40s: tap TAP ME or ping on the tablet --\n")
    (let ((pushes-before (gethash "app:smoke"
                                  (ebp-client-revisions client)))
          (deadline (+ (float-time) 40)))
      (while (< (float-time) deadline)
        (accept-process-output nil 0.2))
      (smoke-floor--check "a device tap ran a buffer effect"
                          smoke-floor--tapped
                          (if smoke-floor--tapped "TAP ME pressed"
                            "no tap seen"))
      ;; The tap's whole point: a mutation re-pushes the showing surface,
      ;; so the tablet reflects the new state without Emacs being asked.
      (let ((after (gethash "app:smoke" (ebp-client-revisions client))))
        (smoke-floor--check "the tap re-pushed the surface"
                            (and after pushes-before (> after pushes-before))
                            (format "revision %s -> %s"
                                    pushes-before after)))))

  (ebp-client-close client 'smoke-done))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-floor--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-floor--fails))
(kill-emacs (if (zerop smoke-floor--fails) 0 1))
