;;; jetpacs-clip.el --- Kill ring on the device, one tap to its clipboard -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JA-1 of docs/PLAN-jetpacs-apps.md: the kill-ring -> clipboard view,
;; the poc jetpacs-tools.el slice the verdict pass rated the best
;; value-for-effort in its cluster (the hub/drawer defers to the JA-2
;; chrome kit; the owner string "tools" stays reserved for it — owner
;; strings are permanent wire identifiers).
;;
;; The load-bearing property: each row's copy button is a
;; `clipboard.copy' BUILTIN descriptor, so the copy executes
;; DEVICE-SIDE from the cached surface — it works with the socket down.
;; The descriptor carries the full (capped) text with real newlines;
;; only the on-screen preview is flattened to one line.
;;
;; Three hard rules from the base this module exists to demonstrate:
;; GATE 1b SIGNALS on an unadvertised builtin, so every row pre-checks
;; `jetpacs-builtin-advertised-p' and degrades to selectable text;
;; kill text is sanitized (`jetpacs-scalar-text') BEFORE the byte cap,
;; because sanitizing swaps 1-byte raw bytes for 3-byte U+FFFD and the
;; other order can land over the cap; and the kill-new advice body is
;; two reads and a timer poke — a disconnected desktop Emacs must not
;; be able to tell this module is loaded.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)

(defgroup jetpacs-clip nil
  "The kill ring mirrored to the Companion clipboard."
  :group 'jetpacs)

(defcustom jetpacs-clip-max-entries 30
  "Kills shown on the device.
Every kill re-pushes the full snapshot, so this bounds per-kill wire
cost, not memory; the frame ceiling is nowhere near the constraint."
  :type 'natnum)

(defcustom jetpacs-clip-entry-bytes 4096
  "Byte cap per entry's copyable text.
Over-cap entries are truncated at a char boundary and visibly marked;
silently uncopyable big kills would defeat the module's point."
  :type 'natnum)

(defcustom jetpacs-clip-preview-chars 120
  "Character cap for the one-line preview."
  :type 'natnum)

(defcustom jetpacs-clip-auto-refresh t
  "When non-nil, every kill re-pushes the view (debounced).
NOTE the Companion currently shows ONE app surface, last push wins —
with several owners live, every desktop kill claims the tablet screen
for this view.  Turn this off and use \\[jetpacs-clip-show] if that
bites."
  :type 'boolean)

(defconst jetpacs-clip-owner "jetpacs.clip"
  "The owner string; also the surface name (app:jetpacs.clip).
PERMANENT: SPEC 13.5 persists the device snapshot keyed by surface id,
so a later rename orphans whatever the device already cached.  The
`jetpacs.' prefix is RESERVED for base (audit R1): a third-party Tier-1
must pick its own namespace, and base must never squat an unqualified
name a package author would reach for.")

(defvar jetpacs-clip--refresh-timer nil)

;;;; Pure text shaping

(defun jetpacs-clip--truncate-bytes (s cap)
  "S cut to at most CAP bytes at a char boundary; returns (TEXT . TRUNCATED-P).
`substring' never splits an Emacs char, so the result is always valid
scalar text; the cap is `string-bytes', not `length' — a 2000-char
euro-sign string is 6000 bytes."
  (if (<= (string-bytes s) cap)
      (cons s nil)
    (let ((n (min (length s) cap)))
      (while (> (string-bytes (substring s 0 n)) cap)
        (setq n (- n (max 1 (/ (- (string-bytes (substring s 0 n)) cap) 4)))))
      (cons (substring s 0 n) t))))

(defun jetpacs-clip--preview (s)
  "One-line preview of already-sanitized S.
Whitespace runs collapse to single spaces; over-length gets an
ellipsis; a whitespace-only kill reads \"(whitespace)\" — an empty
string is a legal but untappable zero-glyph row."
  (let ((flat (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " s))))
    (cond
     ((string-empty-p flat) "(whitespace)")
     ((> (length flat) jetpacs-clip-preview-chars)
      (concat (substring flat 0 jetpacs-clip-preview-chars) "…"))
     (t flat))))

;;;; The view

(defun jetpacs-clip--entry-card (text copy-ok)
  "One kill's card.  Sanitize FIRST, then cap, then preview.
With COPY-OK, the trailing icon button carries the full capped text in
a `clipboard.copy' builtin — real newlines intact, it IS the clipboard
payload.  Without it (builtin unadvertised) there is no button
anywhere and the preview is `:selectable' so native long-press
selection is the fallback."
  (pcase-let* ((clean (jetpacs-scalar-text (substring-no-properties text)))
               (`(,full . ,truncp)
                (jetpacs-clip--truncate-bytes clean jetpacs-clip-entry-bytes))
               (preview (jetpacs-clip--preview full)))
    (jetpacs-card
     (list
      (jetpacs-row
       (jetpacs-with-attrs
        (jetpacs-box
         (delq nil
               (list (if copy-ok
                         (jetpacs-text preview :style "body" :max-lines 1)
                       (jetpacs-text preview :style "body" :max-lines 1
                                     :selectable t))
                     (and truncp
                          (jetpacs-text "first 4 KB" :style "caption")))))
        :weight 1)
       (and copy-ok
            (jetpacs-icon-button
             "content_copy" (jetpacs-clipboard-copy full)
             :content-description "Copy to device clipboard")))))))

(defun jetpacs-clip--view ()
  "The root builder: a scaffold over the newest kills.
A PURE READ of `kill-ring' — never `current-kill', which can query the
OS clipboard and PUSH onto the ring inside a builder (the write-ban)."
  (let* ((kills (seq-take kill-ring jetpacs-clip-max-entries))
         (copy-ok (jetpacs-builtin-advertised-p "clipboard.copy")))
    (jetpacs-scaffold
     :body
     (if (null kills)
         (jetpacs-empty-state :icon "content_paste"
                              :title "Kill ring is empty"
                              :caption "Text killed in Emacs shows up here.")
       (apply #'jetpacs-lazy-column
              (cons (jetpacs-text (format "%d of %d kills, newest first"
                                          (length kills) (length kill-ring))
                                  :style "caption")
                    (mapcar (lambda (k) (jetpacs-clip--entry-card k copy-ok))
                            kills))))
     :on-refresh (jetpacs-action "jetpacs.clip.refresh"))))

;;;; Refresh: device pull + desktop kills

(defun jetpacs-clip--refresh-now ()
  "Push the view now, quietly; timer target."
  (setq jetpacs-clip--refresh-timer nil)
  (when (jetpacs-connected-p)
    (condition-case err
        (jetpacs-shell-push jetpacs-clip-owner)
      (error (message "jetpacs-clip: push failed: %s"
                      (jetpacs-error-label err))))))

(defun jetpacs-clip--schedule-refresh ()
  "Debounced refresh; kill storms collapse to one push."
  (when (timerp jetpacs-clip--refresh-timer)
    (cancel-timer jetpacs-clip--refresh-timer))
  (setq jetpacs-clip--refresh-timer
        (run-with-idle-timer 0.7 nil #'jetpacs-clip--refresh-now)))

(defun jetpacs-clip--after-kill (&rest _)
  "The `kill-new' advice: two reads and a timer poke, nothing else.
Covers kill-region/kill-ring-save/kill-append (kill-append delegates to
kill-new).  Behaviorally invisible to a disconnected desktop Emacs."
  (when (and jetpacs-clip-auto-refresh (jetpacs-connected-p))
    (jetpacs-clip--schedule-refresh)))

(defun jetpacs-clip-show ()
  "Push the kill-ring view to the device now, loudly."
  (interactive)
  (jetpacs-client-or-error)
  (jetpacs-shell-push jetpacs-clip-owner)
  (message "jetpacs-clip: pushed %d entries"
           (min (length kill-ring) jetpacs-clip-max-entries)))

;;;; Registration

(with-jetpacs-owner "jetpacs.clip"
  (jetpacs-shell-define-root jetpacs-clip-owner #'jetpacs-clip--view)
  (jetpacs-defaction "jetpacs.clip.refresh"
    (lambda (_args params)
      ;; D1: the ORIGINATING surface.  `jetpacs--dispatch' does bind
      ;; this action's owner now, so a zero-arg push would resolve
      ;; correctly — but the wire names the surface the user actually
      ;; tapped, and honouring it is what makes one owner's view
      ;; refreshable from more than one of its surfaces.  D2: the
      ;; re-push is the deferred refresh; the status returns now.
      (let ((surface (or (plist-get params :surface)
                         (concat "app:" jetpacs-clip-owner))))
        (jetpacs-flow-continue
         (lambda ()
           (condition-case err
               (jetpacs-shell-push surface)
             (error (message "jetpacs-clip: refresh push failed: %s"
                             (jetpacs-error-label err))))))
        'accepted))))

(advice-add 'kill-new :after #'jetpacs-clip--after-kill)

(defun jetpacs-clip-unload-function ()
  "Unload hygiene: drop the advice, the timer, and the surface."
  (advice-remove 'kill-new #'jetpacs-clip--after-kill)
  (when (timerp jetpacs-clip--refresh-timer)
    (cancel-timer jetpacs-clip--refresh-timer)
    (setq jetpacs-clip--refresh-timer nil))
  (ignore-errors (jetpacs-shell-remove-root jetpacs-clip-owner))
  nil)

(provide 'jetpacs-clip)
;;; jetpacs-clip.el ends here
