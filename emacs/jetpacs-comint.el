;;; jetpacs-comint.el --- Generic comint renderer (Tier 0.5) -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Tier 0.5: `comint-mode' is the substrate under every process REPL — M-x
;; shell, ielm, the inferior language shells — so ONE skin covers them all.
;; The transcript renders through the Tier 0 walk (fontification and
;; tappable regions survive), tail-first because a REPL's interesting end
;; is the bottom; below it sit a status/interrupt row and an input row
;; whose submit dispatches `comint.send'.
;;
;; Boundary: `comint.send' delivers input only to the live process of an
;; ALREADY-OPEN comint buffer — a REPL the user opened themselves.  It
;; never starts a process, so the wire gains no execution surface beyond
;; the sanctioned M-x escape hatch (SPEC 23.2).
;;
;; The input's widget id stays stable across background transcript pushes
;; — SPEC 13.6's draft reconciliation then preserves half-typed text — and
;; rotates after each send, which is how a server-driven client clears a
;; field.
;;
;; Rung JC-3c of docs/PLAN-jetpacs-consumers.md.
;;
;; Known gap (unchanged from poc-v1): a password prompt raised from the
;; process filter (`comint-watch-for-password-prompt') runs outside any
;; action handler, so it is not bridged to the phone; it blocks in the
;; desktop minibuffer like any other filter-time prompt.

;;; Code:

(require 'cl-lib)
(require 'comint)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-buffer)

(defcustom jetpacs-comint-tail-lines 200
  "Transcript lines rendered from the tail of a comint buffer."
  :type 'integer :group 'jetpacs)

(defvar jetpacs-comint--gen (make-hash-table :test 'equal)
  "Buffer name -> send counter, spliced into the input's widget id.
A send bumps it, handing the client a fresh (empty) field; a background
transcript refresh does not, so SPEC 13.6 keeps half-typed input.")

(defun jetpacs-comint--refresh (params)
  "Re-push the surface the event came from, deferred.
The seam takes a surface as of JC-1: under decision D1 every owner has
its own, so a zero-arg call would refresh the wrong one.  Deferred
because `jetpacs-shell-push' signals on a gate failure, which must not
escape after the send already went to the process."
  (let ((surface (plist-get params :surface)))
    (run-at-time
     0 nil
     (lambda ()
       (when (functionp jetpacs-buffer-refresh-function)
         (condition-case err
             (funcall jetpacs-buffer-refresh-function surface)
           (error (message "jetpacs-comint: refresh failed: %s"
                           (jetpacs--error-label err)))))))))

;; --- Rendering ---------------------------------------------------------------

(defun jetpacs-comint-render (buf)
  "Tier-1 skin: comint BUF as status row + transcript tail + input row."
  (with-current-buffer buf
    (let* ((name (buffer-name))
           (proc (get-buffer-process buf))
           (live (and proc (process-live-p proc)))
           (status (if live
                       (format "%s — %s" (process-name proc)
                               (process-status proc))
                     "no live process"))
           (interrupt (and live
                           (jetpacs-action "comint.interrupt"
                                           :args (list :buffer name)))))
      (append
       (list (apply
              #'jetpacs-row
              (delq nil
                    (list (jetpacs-with-attrs
                           (jetpacs-box (jetpacs-text status :style "caption"))
                           :weight 1)
                          (when interrupt
                            ;; `icon_button' is OPTIONAL (SPEC 16.2).
                            (if (jetpacs-node-advertised-p "icon_button")
                                (jetpacs-icon-button
                                 "stop" interrupt
                                 :content-description "Interrupt (C-c C-c)")
                              (jetpacs-button "Stop" interrupt)))))))
       ;; The tail goes through the Tier-0 walk, so its spans are
       ;; sanitized and its tap positions exposed for `emacs.buffer.act'.
       (jetpacs-buffer-render-tail buf jetpacs-comint-tail-lines)
       (when live
         ;; The input row is the scroll target: it sits at the bottom and
         ;; every output line shifts its index, so the view follows the
         ;; transcript — the terminal "tail -f" feel.  `text_input' is Core,
         ;; so this needs no degrade.
         (list (jetpacs-with-attrs
                (jetpacs-text-input
                 (format "comint/%s/%d" name
                         (gethash name jetpacs-comint--gen 0))
                 :hint "Input — Enter sends"
                 :single-line t :monospace t
                 :on-submit (jetpacs-action "comint.send"
                                            :args (list :buffer name)))
                :scroll_here t)))))))

(jetpacs-render-buffer-register 'comint-mode #'jetpacs-comint-render)

;; --- Actions -----------------------------------------------------------------

(defun jetpacs-comint--live-buffer (name)
  "The comint buffer NAME when it has a live process, else nil.
The gate for both wire actions (SPEC 23.1): a name off the wire can only
ever reach the process of an already-open comint buffer."
  (let ((buf (and (stringp name) (get-buffer name))))
    (and buf
         (with-current-buffer buf (derived-mode-p 'comint-mode))
         (let ((proc (get-buffer-process buf)))
           (and proc (process-live-p proc)))
         buf)))

(jetpacs-defaction "comint.send"
  ;; SPEC 14.3: `on_submit' injects the submitted text as `value' into a
  ;; copy of the descriptor's args (only a PASSWORD submission uses
  ;; `fields'), so the input arrives in ARGS.
  (lambda (args params)
    (let ((buf (jetpacs-comint--live-buffer (plist-get args :buffer)))
          (input (plist-get args :value)))
      (cond
       ;; No such buffer, wrong mode, or no live process: nothing will ever
       ;; make this event deliverable.
       ((null buf) 'rejected)
       ((not (stringp input)) 'rejected)
       (t
        ;; Synchronous, so `accepted' names input the process really got
        ;; (SPEC 14.4); a failure answers `rejected' rather than claiming
        ;; delivery.
        (with-current-buffer buf
          (goto-char (point-max))
          (insert input)
          (comint-send-input))
        (cl-incf (gethash (buffer-name buf) jetpacs-comint--gen 0))
        (jetpacs-comint--refresh params)
        'accepted)))))

(jetpacs-defaction "comint.interrupt"
  (lambda (args params)
    (let ((buf (jetpacs-comint--live-buffer (plist-get args :buffer))))
      (if (null buf)
          'rejected
        (with-current-buffer buf
          (comint-interrupt-subjob))
        (jetpacs-comint--refresh params)
        'accepted))))

(provide 'jetpacs-comint)
;;; jetpacs-comint.el ends here
