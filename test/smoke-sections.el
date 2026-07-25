;;; smoke-sections.el --- JC-3a + Phase C device gate -*- lexical-binding: t; -*-

;; Drives the magit-section skin against a live Companion with a REAL
;; `magit-status'.  The ERT cannot cover any of this: magit is not loaded
;; in the suite, so registration never fires, `commandp' rejects every
;; magit symbol before the denylist is consulted, and there is no 60-entry
;; keymap to overflow the menu.
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(dolist (d (directory-files "~/.emacs.d/elpa" t "\\`[^.]"))
  (when (file-directory-p d) (add-to-list 'load-path d)))
(require 'magit)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-results)
(require 'jetpacs-sections)

(defvar smoke-s--fails 0)
(defun smoke-s--check (label ok &optional detail)
  (princ (format "%-46s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-s--fails (1+ smoke-s--fails))))

(defvar smoke-s--ready nil)
(defvar smoke-s--menus 0)

(defvar smoke-s--buf
  (let ((default-directory
         (expand-file-name "~/pkb/projects/jetpacs/jetpacs/llm-poc-2/")))
    (save-window-excursion (magit-status))
    (magit-get-mode-buffer 'magit-status-mode)))

(let ((client
       (jetpacs-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme" "surfaces.dialog")
        :receipt-file (make-temp-file "smoke-sections-receipts")
        :ready-function (lambda (_c) (setq smoke-s--ready t)))))

  (smoke-s--check "a real magit-status buffer" (buffer-live-p smoke-s--buf))
  ;; Registration itself is smoke-only (`with-eval-after-load').
  (smoke-s--check "the JC-3a skin claims magit-section-mode"
                  (eq (with-current-buffer smoke-s--buf
                        (seq-some (lambda (c)
                                    (and (derived-mode-p (car c)) (cdr c)))
                                  jetpacs-render-buffer-functions))
                      #'jetpacs-sections-render))

  ;; C16 against the real keymap.
  (with-current-buffer smoke-s--buf
    (goto-char (point-min))
    (forward-line 3)
    (let* ((cands (jetpacs-sections--menu-candidates (point)))
           (keys (mapcar #'cdr cands)))
      (smoke-s--check "menu is phone-sized, not magit's whole keymap"
                      (<= (length cands) jetpacs-sections-menu-max)
                      (format "%d entries: %S" (length cands) keys))
      (smoke-s--check "magit's stage/unstage reach the menu (C16)"
                      (and (member "s" keys) (member "u" keys)))
      (smoke-s--check "destructive verbs are NOT offered"
                      (null (seq-intersection '("k" "x" "X") keys))
                      (format "%S" (seq-intersection '("k" "x" "X") keys)))))

  (let ((real (gethash "sections.menu" jetpacs-action-handlers)))
    (puthash "sections.menu"
             (lambda (args params)
               (cl-incf smoke-s--menus)
               (funcall real args params))
             jetpacs-action-handlers))

  (with-jetpacs-owner "sections"
    (jetpacs-shell-define-root
     "sections"
     (lambda () (apply #'jetpacs-column
                       (jetpacs-render-buffer smoke-s--buf)))))

  ;; Generous: this smoke loads all of elpa plus magit before connecting.
  (let ((deadline (+ (float-time) 40)))
    (while (and (not smoke-s--ready) (< (float-time) deadline))
      (accept-process-output nil 0.1)))
  (smoke-s--check "session reaches READY" smoke-s--ready)

  (when smoke-s--ready
    (smoke-s--check "surfaces.dialog granted (the menu needs it)"
                    (seq-contains-p (ebp-client-granted client) "surfaces.dialog")
                    (format "%S" (append (ebp-client-granted client) nil)))
    (with-jetpacs-owner "sections"
      (smoke-s--check "magit tree pushed through every gate"
                      (integerp (jetpacs-shell-push))))
    ;; C1: every emitted card id must be unique, or the push is 1201.
    (let* ((nodes (jetpacs-sections-render smoke-s--buf))
           (ids nil))
      (cl-labels ((walk (n)
                    (when (plist-get n :id) (push (plist-get n :id) ids))
                    (mapc #'walk (append (plist-get n :children) nil))))
        (mapc #'walk nodes))
      (smoke-s--check "every card id is unique (C1/SPEC 16.1)"
                      (= (length ids) (length (delete-dups (copy-sequence ids))))
                      (format "%d ids" (length ids))))

    (princ "\n  -- 45s: long-press a section header --\n")
    (let ((deadline (+ (float-time) 45)))
      (while (< (float-time) deadline)
        (accept-process-output nil 0.2)))
    (smoke-s--check "a sections.menu event arrived from the device"
                    (> smoke-s--menus 0)
                    (format "%d menu(s)" smoke-s--menus)))

  (ebp-client-close client 'smoke-done))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-s--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-s--fails))
(kill-emacs (if (zerop smoke-s--fails) 0 1))
