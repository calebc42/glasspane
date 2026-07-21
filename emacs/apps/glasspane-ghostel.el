;;; glasspane-ghostel.el --- Tier 1 buffer skin for Ghostel terminals -*- lexical-binding: t; -*-

;; A shell on your phone, not a terminal emulator on your phone: the
;; Ghostel buffer (ghostel-mode, the libghostty-vt terminal) renders as
;; a transcript tail plus an input row, the same shape as the comint
;; skin (jetpacs-comint.el in the core) that this file is modeled on.
;; Ghostel keeps its screen as ordinary buffer text with faces, so the
;; Tier 0 walk carries true color and bold to the device for free; a
;; curated chip row (Esc/Tab/arrows/^C/^D) covers the keys a line-input
;; model can't express.
;;
;; Boundary (jetpacs docs/SPEC.md §5): both actions deliver input only to
;; the live process of an existing ghostel buffer — a terminal the user
;; already opened.  They never start one, so the wire gains no new
;; execution surface beyond what `comint.send' already sanctions.
;; `ghostel.send-key' is tighter still: the key vocabulary is the
;; enumerable allowlist in `glasspane-ghostel--keys'.
;;
;; Every action here is `:when-offline "drop"', deliberately diverging
;; from comint's queue default: a terminal's screen moves under you
;; (prompts, pagers, TUIs), so replaying stale input against an unknown
;; screen is worse than losing it.
;;
;; Known gaps, inherent to the input-row model:
;; - A TTY password prompt can't reach the phone field's masking; typed
;;   secrets echo in the input row (the comint skin documents the same
;;   class of gap for filter-time prompts).
;; - Kitty-graphics images ride display properties the span walk doesn't
;;   ship; they simply don't appear.
;; - Full-screen TUIs refresh at the live-watch cadence (~1 s snapshot),
;;   and their fixed-column grids shear at phone widths.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-buffer)

;; Ghostel is a third-party package; nothing here requires it at load
;; time.  The renderer only dispatches for buffers whose major mode IS
;; ghostel-mode, and the actions gate on the same, so these resolve by
;; the time they can be called.
(declare-function ghostel-send-string "ghostel" (string))
(declare-function ghostel-send-key "ghostel" (key-name &optional mods))
(defvar ghostel--process)  ; buffer-local lifecycle process, both PTY paths

(defcustom glasspane-ghostel-tail-lines 200
  "Transcript lines rendered from the tail of a ghostel buffer."
  :type 'integer :group 'jetpacs)

(defconst glasspane-ghostel--keys
  '(("Esc" "escape" "")
    ("Tab" "tab" "")
    ("↑"   "up" "")
    ("↓"   "down" "")
    ("^C"  "c" "ctrl")
    ("^D"  "d" "ctrl"))
  "Key chips offered on the device: (LABEL KEY-NAME MODS).
Doubles as the `ghostel.send-key' allowlist — the wire can press
exactly these keys, nothing else.")

(defvar glasspane-ghostel--gen (make-hash-table :test 'equal)
  "Buffer name -> send counter, spliced into the input's widget id.
A send bumps it, handing the client a fresh (empty) field; background
transcript refreshes don't, so the seed guard keeps half-typed input.")

(defun glasspane-ghostel--refresh ()
  (when (functionp jetpacs-buffer-refresh-function)
    (funcall jetpacs-buffer-refresh-function)))

(defun glasspane-ghostel--live-p (buf)
  "Non-nil when BUF is a ghostel buffer with a live terminal process.
Checks the buffer-local `ghostel--process', the same handle ghostel's
own kill-buffer guard uses — it is the shell process when Emacs owns
the PTY and the native event pipe when libghostty does."
  (and (buffer-live-p buf)
       (with-current-buffer buf
         (and (derived-mode-p 'ghostel-mode)
              (boundp 'ghostel--process)
              (processp ghostel--process)
              (process-live-p ghostel--process)))))

;; ─── Rendering ───────────────────────────────────────────────────────────────

(defun glasspane-ghostel--key-row (name)
  "The curated key-chip row for ghostel buffer NAME."
  (apply #'jetpacs-scroll-row
         (mapcar (pcase-lambda (`(,label ,key ,mods))
                   (jetpacs-chip label
                              :on-tap (jetpacs-action "ghostel.send-key"
                                                   :args `((buffer . ,name)
                                                           (key . ,key)
                                                           (mods . ,mods))
                                                   :when-offline "drop")))
                 glasspane-ghostel--keys)))

(defun glasspane-ghostel-render (buf)
  "Tier-1 skin: ghostel BUF as status row + transcript tail + keys + input."
  (with-current-buffer buf
    (let* ((name (buffer-name))
           (live (glasspane-ghostel--live-p buf)))
      (append
       (list (jetpacs-text
              (if live
                  (format "%s — %s" (process-status ghostel--process)
                          (abbreviate-file-name default-directory))
                "no live process")
              'caption))
       (jetpacs-buffer-render-tail buf glasspane-ghostel-tail-lines)
       (when live
         (list
          (glasspane-ghostel--key-row name)
          ;; The input row is the scroll target: it sits at the bottom, and
          ;; every output line shifts its index, so the view follows the
          ;; transcript — the terminal "tail -f" feel.
          (jetpacs-scroll-here
           (jetpacs-text-input
            (format "ghostel/%s/%d" name (gethash name glasspane-ghostel--gen 0))
            :hint "Input — Enter sends"
            :single-line t :monospace t
            :on-submit (jetpacs-action "ghostel.send"
                                    :args `((buffer . ,name))
                                    :when-offline "drop")))))))))

(jetpacs-render-buffer-register 'ghostel-mode #'glasspane-ghostel-render)

;; ─── Actions ─────────────────────────────────────────────────────────────────

(defun glasspane-ghostel--live-buffer (name)
  "The ghostel buffer NAME when it has a live process, else nil (messaged).
The gate for both wire actions: an arbitrary name off the wire can only
ever reach the process of an already-open ghostel buffer."
  (let ((buf (and (stringp name) (get-buffer name))))
    (cond
     ((not (and buf (with-current-buffer buf (derived-mode-p 'ghostel-mode))))
      (message "%s is not a ghostel buffer" (or name "?"))
      nil)
     ((not (glasspane-ghostel--live-p buf))
      (message "%s has no live process" name)
      nil)
     (t buf))))

(with-jetpacs-owner "ghostel"

  (jetpacs-defaction "ghostel.send"
    (lambda (args _)
      (let ((buf (glasspane-ghostel--live-buffer (alist-get 'buffer args)))
            (input (alist-get 'value args)))
        (when buf
          (condition-case err
              (with-current-buffer buf
                ;; Ghostel's own line mode: write the input, then submit an
                ;; encoded Return (respects Kitty protocol / app modes).
                ;; An empty submit is a bare Enter — re-run, accept default.
                (when (and (stringp input) (> (length input) 0))
                  ;; The PTY takes raw bytes; encoding is the caller's job
                  ;; per the `ghostel-send-string' contract.
                  (ghostel-send-string (encode-coding-string input 'utf-8)))
                (ghostel-send-key "return"))
            (error (message "Send failed: %s" (error-message-string err))))
          (cl-incf (gethash (buffer-name buf) glasspane-ghostel--gen 0))
          (glasspane-ghostel--refresh)))))

  (jetpacs-defaction "ghostel.send-key"
    (lambda (args _)
      (let ((buf (glasspane-ghostel--live-buffer (alist-get 'buffer args)))
            (key (alist-get 'key args))
            (mods (or (alist-get 'mods args) "")))
        (when buf
          (if (not (seq-find (pcase-lambda (`(,_ ,k ,m))
                               (and (equal key k) (equal mods m)))
                             glasspane-ghostel--keys))
              (message "ghostel: key %S %S not allowlisted" key mods)
            (condition-case err
                (with-current-buffer buf
                  (ghostel-send-key key (unless (string-empty-p mods) mods)))
              (error (message "Send failed: %s" (error-message-string err))))
            (glasspane-ghostel--refresh)))))))

(provide 'glasspane-ghostel)
;;; glasspane-ghostel.el ends here
