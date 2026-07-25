;;; smoke-results.el --- JC-2 device gate -*- lexical-binding: t; -*-

;; Drives the results skin against a live Companion with a REAL `occur':
;;
;;   occur over a real buffer -> jetpacs-render-buffer dispatches to the
;;   JC-2 skin -> result cards push -> tap a card -> results.visit runs the
;;   mode's own goto (shimmed) -> the region view re-pushes showing the
;;   source location with prev/next chrome -> tap Next -> results.step.
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-results)
(require 'jetpacs-tablist)

(defvar smoke-results--fails 0)
(defun smoke-results--check (label ok &optional detail)
  (princ (format "%-46s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-results--fails (1+ smoke-results--fails))))

;; A real source buffer, and a real `occur' over it.
(defvar smoke-results--src
  (with-current-buffer (get-buffer-create "*smoke-src*")
    (erase-buffer)
    (dotimes (i 12)
      (insert (format "line %02d %s\n" i (if (cl-evenp i) "MATCH here" "quiet"))))
    (goto-char (point-min))
    (current-buffer)))

(defvar smoke-results--occur nil)
(defvar smoke-results--ready nil)

(let ((client
       (jetpacs-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme")
        :receipt-file (make-temp-file "smoke-results-receipts")
        :ready-function (lambda (_c) (setq smoke-results--ready t)))))

  ;; Build the real occur buffer.
  (with-current-buffer smoke-results--src
    (save-window-excursion (occur "MATCH")))
  (setq smoke-results--occur (get-buffer "*Occur*"))
  (smoke-results--check "a real *Occur* buffer exists"
                        (and smoke-results--occur t))
  (smoke-results--check "the JC-2 skin claims occur-mode"
                        (eq (with-current-buffer smoke-results--occur
                              (seq-some (lambda (c)
                                          (and (derived-mode-p (car c)) (cdr c)))
                                        jetpacs-render-buffer-functions))
                            #'jetpacs-results-render))

  (with-jetpacs-owner "results"
    (jetpacs-shell-define-root
     "results"
     (lambda ()
       (apply #'jetpacs-column
              (append
               (list (jetpacs-text "JC-2 results skin" :style "headline"))
               ;; The region view when a visit is armed, else the result list.
               (or (jetpacs-results-region-nodes)
                   (jetpacs-render-buffer smoke-results--occur)))))))

  (let ((deadline (+ (float-time) 20)))
    (while (and (not smoke-results--ready) (< (float-time) deadline))
      (accept-process-output nil 0.1)))
  (smoke-results--check "session reaches READY" smoke-results--ready)

  (when smoke-results--ready
    (let ((loci (jetpacs-results--loci smoke-results--occur)))
      (smoke-results--check "loci parsed from the real occur buffer"
                            (= (length loci) 6)
                            (format "%d loci" (length loci))))
    (with-jetpacs-owner "results"
      (smoke-results--check "result list pushed"
                            (integerp (jetpacs-shell-push))))
    ;; Every card's position must be exposed, else its tap is refused.
    (let ((loci (jetpacs-results--loci smoke-results--occur)))
      (smoke-results--check
       "every rendered locus is exposed (SPEC 23.1)"
       (cl-every (lambda (l)
                   (and (jetpacs-buffer-exposed-p
                         (buffer-name smoke-results--occur)
                         (car l) "results.visit")
                        ;; ...and ONLY for its own verb.
                        (not (jetpacs-buffer-exposed-p
                              (buffer-name smoke-results--occur)
                              (car l) "emacs.buffer.act"))))
                 loci)))

    (princ "\n  -- 45s: tap a result card, then Next --\n")
    (let ((deadline (+ (float-time) 45)))
      (while (< (float-time) deadline)
        (accept-process-output nil 0.2)))

    (smoke-results--check "a tap armed the stepper"
                          (and jetpacs-results--nav t)
                          (format "index %s of %s in %s"
                                  (plist-get jetpacs-results--nav :index)
                                  (plist-get jetpacs-results--nav :count)
                                  (plist-get jetpacs-results--nav :dest)))
    (smoke-results--check "the region view is armed"
                          (and jetpacs-results--region t)
                          (plist-get jetpacs-results--region :label)))

  (ebp-client-close client 'smoke-done))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-results--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-results--fails))
(kill-emacs (if (zerop smoke-results--fails) 0 1))
