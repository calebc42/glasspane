;;; smoke-ja3.el --- JA-3 device gate: the general Emacs client -*- lexical-binding: t; -*-

;; The plan's exit smoke (PLAN-jetpacs-apps.md JA-3): list buffers,
;; drill into one, run M-x, invoke a palette entry from a mode with no
;; registered skin.  Driven by a runner watching the P*-TAP-* markers:
;;
;;   P1-TAP-ROW      tap the "ja3-target.txt" row in the hub
;;   P2-TAP-FAB      tap the keyboard FAB (content-desc "command palette"),
;;                   then in the dialog tap the option containing
;;                   "T  ·" and then OK
;;   P3-TAP-BACK-MX  tap arrow_back, then the M-x icon (desc "M-x"),
;;                   type "emacs-version" into the dialog field, tap OK
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-dialog)
(require 'jetpacs-navigate)
(require 'jetpacs-chrome)
(require 'jetpacs-emacs-ui)

(defvar smoke-j3--fails 0)
(defun smoke-j3--check (label ok &optional detail)
  (princ (format "%-52s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-j3--fails (1+ smoke-j3--fails))))
(defun smoke-j3--drain (secs &optional stop-fn)
  (let ((deadline (+ (float-time) secs)))
    (while (and (< (float-time) deadline)
                (not (and stop-fn (funcall stop-fn))))
      (accept-process-output nil 0.1))))
(defun smoke-j3--mark (m) (princ (concat m "\n")) (message "%s" m))

;; The unskinned target buffer: fundamental-mode, one local binding the
;; palette must surface and execute.
(defun smoke-j3-insert-tapped ()
  (interactive)
  (goto-char (point-max))
  (insert "TAPPED\n"))
(with-current-buffer (get-buffer-create "ja3-target.txt")
  (fundamental-mode)
  (erase-buffer)
  (insert "hello ja3\n")
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "T") #'smoke-j3-insert-tapped)
    (use-local-map map)))

(let ((client
       (jetpacs-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("presentation.toast" "surfaces.dialog")
        :receipt-file (make-temp-file "smoke-j3-receipts"))))
  (ignore client)
  (smoke-j3--drain 20 (lambda () (jetpacs-connected-p)))
  (smoke-j3--check "session reaches READY" (jetpacs-connected-p))

  (when (jetpacs-connected-p)
    ;; The hub.
    (let ((rev (condition-case err
                   (jetpacs-shell-push jetpacs-emacs-ui-owner)
                 (error (message "push failed: %S" err) nil))))
      (smoke-j3--check "hub pushed" (integerp rev) (format "%S" rev)))
    (smoke-j3--drain 2)

    ;; P1: the runner taps the target row.
    (smoke-j3--mark "P1-TAP-ROW")
    (let ((want-id (jetpacs-wire-id "buf" "ja3-target.txt")))
      (smoke-j3--drain 150
                       (lambda ()
                         (equal (car (jetpacs-chrome-stack
                                      jetpacs-emacs-ui-owner))
                                want-id)))
      (smoke-j3--check "row tap drilled into the buffer"
                       (equal (car (jetpacs-chrome-stack
                                    jetpacs-emacs-ui-owner))
                              want-id)))

    ;; P2: the palette on an unskinned mode.
    (smoke-j3--mark "P2-TAP-FAB")
    (smoke-j3--drain 150
                     (lambda ()
                       (with-current-buffer "ja3-target.txt"
                         (save-excursion
                           (goto-char (point-min))
                           (search-forward "TAPPED" nil t)))))
    (smoke-j3--check "palette entry executed in the buffer"
                     (with-current-buffer "ja3-target.txt"
                       (save-excursion
                         (goto-char (point-min))
                         (search-forward "TAPPED" nil t))))

    ;; P3: back to the hub, then M-x emacs-version.
    (smoke-j3--mark "P3-TAP-BACK-MX")
    (let ((probe (lambda ()
                   (with-current-buffer "*Messages*"
                     (save-excursion
                       (goto-char (point-max))
                       (search-backward "GNU Emacs" nil t))))))
      (smoke-j3--drain 180 probe)
      (smoke-j3--check "M-x emacs-version ran via the bridged picker"
                       (funcall probe))))

  (princ (format "\nSMOKE %s (%d failure(s))\n"
                 (if (zerop smoke-j3--fails) "PASS" "FAIL")
                 smoke-j3--fails))
  (kill-emacs (min smoke-j3--fails 1)))

;;; smoke-ja3.el ends here
