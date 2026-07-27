;;; jetpacs-emacs-ui.el --- The general Emacs client -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JA-3c: what turns the tablet from "a viewer for whatever a skin
;; pushed" into a general Emacs client — a buffer list, drill-in to any
;; buffer through the Tier-0 renderer (skins apply automatically via
;; `jetpacs-render-buffer'), a *Messages* tail, imenu navigation, the
;; M-x runner, and the command palette over `jetpacs-keymap''s
;; extraction and menu-bar mining.
;;
;; Rebuilt from poc-v1's jetpacs-emacs-ui.el on the JA-2 floor rather
;; than ported: the poc's tab views, drawer items and top-action
;; registries do not exist here — screens live on ONE chrome stack
;; (`jetpacs-chrome-define-root' + push/pop), the drill state that was
;; a module global lives in the stack itself, and the imenu slice state
;; belongs to `jetpacs-results' (the plan's mandate: extend the region
;; view, never parallel it).  The eval REPL is deliberately absent —
;; not in JA-3's scope, and SPEC 23.2 makes it a design decision, not a
;; port.
;;
;; The D2 inversions from the poc:
;;   - imenu and M-x ran `completing-read' INSIDE their handlers; here
;;     every prompt runs in a `jetpacs-flow-continue' continuation,
;;     where the dialog bridge routes it to the device.
;;   - Every action answers its SPEC 14.4 status explicitly and defers
;;     its presenting push (`jetpacs-chrome-push-screen' signals on
;;     gate failure; a handler must never let that signal escape as a
;;     spurious `rejected').
;;
;; SPEC 23.1: the buffer list EXPOSES each listed buffer for the view
;; verb, and the drilled screen exposes its buffer for imenu/palette —
;; a tap naming a buffer this Emacs never offered is refused, exactly
;; like a position tap at an offset never rendered.

;;; Code:

(require 'cl-lib)
(require 'imenu)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-commands)
(require 'jetpacs-keymap)
(require 'jetpacs-buffer)
(require 'jetpacs-results)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-navigate)

(defconst jetpacs-emacs-ui-owner "jetpacs.emacs"
  "The base owner of the general-client surface (R1: base's prefix).")

(defconst jetpacs-emacs-ui--surface (concat "app:" jetpacs-emacs-ui-owner))

(defcustom jetpacs-emacs-ui-max-buffers 100
  "Cap on buffers listed in the hub.
The SPEC 4.5 byte budget truncates the render anyway; this keeps the
list itself intentional."
  :type 'natnum :group 'jetpacs)

(defvar jetpacs-emacs-ui--screens (make-hash-table :test #'equal)
  "Screen id -> the buffer NAME that screen presents.
The chrome stack knows ids; the live-refresh watch and the region view
need the buffer behind the top screen.  \"messages\" maps to
*Messages*; the hub maps to nothing.")

;; --- The hub: the buffer list ------------------------------------------------

(defun jetpacs-emacs-ui--buffer-subtitle (buf)
  "One caption line for BUF: its file, or mode and size.
Deliberately not `count-lines' — the poc counted every fileless
buffer's lines on every render."
  (with-current-buffer buf
    (if buffer-file-name
        (abbreviate-file-name buffer-file-name)
      (format "%s · %s chars"
              (string-remove-suffix "-mode" (symbol-name major-mode))
              (buffer-size)))))

(defun jetpacs-emacs-ui--listed-buffers ()
  "Live buffers the hub offers, in `buffer-list' (recency) order."
  (seq-take (seq-remove (lambda (b)
                          (string-prefix-p " " (buffer-name b)))
                        (buffer-list))
            jetpacs-emacs-ui-max-buffers))

(defun jetpacs-emacs-ui--hub-rows ()
  "The hub's rows; records a SPEC 23.1 exposure per listed buffer."
  (mapcar
   (lambda (buf)
     (let ((name (buffer-name buf)))
       (jetpacs-buffer-expose-buffer name "jetpacs.emacs.view")
       (jetpacs-chrome-row
        (if (and (buffer-file-name buf) (buffer-modified-p buf))
            (concat "● " name)
          name)
        :subtitle (jetpacs-emacs-ui--buffer-subtitle buf)
        :on-tap (jetpacs-action "jetpacs.emacs.view"
                                :args (list :buffer name))
        :key (jetpacs-wire-id "buf" name))))
   (jetpacs-emacs-ui--listed-buffers)))

(defun jetpacs-emacs-ui--hub-screen (back)
  "The root screen: Messages row, then every offerable buffer."
  (jetpacs-chrome-screen
   "Buffers"
   (apply #'jetpacs-lazy-column
          (cons (jetpacs-chrome-row
                       "*Messages*"
                       :subtitle "the echo-area log"
                       :icon "description"
                 :on-tap (jetpacs-action "jetpacs.emacs.messages")
                 :key "row-messages")
                (jetpacs-emacs-ui--hub-rows)))
   :back back
   :actions (list (jetpacs-icon-button
                   "terminal" (jetpacs-action "jetpacs.emacs.mx")
                   :content-description "M-x"))))

;; --- The drilled buffer screen -----------------------------------------------

(defun jetpacs-emacs-ui--buffer-screen (name back)
  "The drilled-in screen for buffer NAME.
Body is the armed imenu slice when `jetpacs-results' holds one for
NAME, else the full skin-dispatched render.  Exposes NAME for the
verbs this screen offers — AFTER the render, deliberately: the Tier-0
walk performs the document's superseding clear for its buffer
\(`jetpacs-buffer-forget-exposed' inside `--render-region'), so a
record written before the render is wiped by it.  That clear also eats
the hub row's earlier view record for this buffer (the hub builds
below us in the same document), so the view verb is re-exposed here."
  (let ((buf (get-buffer name)))
    (if (not buf)
        (jetpacs-chrome-screen
         name (jetpacs-empty-state "Buffer is gone") :back back)
      (let ((body
             (apply #'jetpacs-column
                    (if (equal name (jetpacs-results-region-buffer))
                        (append
                         (list (jetpacs-row
                                (jetpacs-with-attrs
                                 (jetpacs-text "Section view"
                                               :style "caption")
                                 :weight 1)
                                (jetpacs-icon-button
                                 "close"
                                 (jetpacs-action "jetpacs.emacs.imenu-clear")
                                 :content-description "whole buffer")
                                :align "center"))
                         (jetpacs-results-region-nodes))
                      (jetpacs-render-buffer buf)))))
        (jetpacs-buffer-expose-buffer name "jetpacs.emacs.view")
        (jetpacs-buffer-expose-buffer name "jetpacs.emacs.imenu")
        (jetpacs-buffer-expose-buffer name "jetpacs.emacs.palette")
        (jetpacs-chrome-screen
         name body
         :back back
         :actions (list (jetpacs-icon-button
                         "toc" (jetpacs-action "jetpacs.emacs.imenu"
                                               :args (list :buffer name))
                         :content-description "imenu"))
         :fab (jetpacs-icon-button
               "keyboard" (jetpacs-action "jetpacs.emacs.palette"
                                          :args (list :buffer name))
               :content-description "command palette"))))))

(defun jetpacs-emacs-ui--push-buffer-screen (name)
  "Push NAME's screen onto our stack; call only from a continuation."
  (let ((id (jetpacs-wire-id "buf" name)))
    (puthash id name jetpacs-emacs-ui--screens)
    (condition-case err
        (jetpacs-chrome-push-screen
         jetpacs-emacs-ui-owner id
         (lambda (back) (jetpacs-emacs-ui--buffer-screen name back)))
      (error (message "jetpacs-emacs-ui: buffer screen push failed: %s"
                      (jetpacs--error-label err))))))

;; --- The Messages screen -----------------------------------------------------

(defcustom jetpacs-emacs-ui-messages-lines 100
  "Lines of *Messages* the tail screen shows."
  :type 'natnum :group 'jetpacs)

(defun jetpacs-emacs-ui--messages-screen (back)
  "The *Messages* tail over `jetpacs-buffer-render-tail'."
  (let ((buf (get-buffer "*Messages*")))
    (jetpacs-chrome-screen
     "*Messages*"
     (if (not buf)
         (jetpacs-empty-state "No messages yet")
       (apply #'jetpacs-column
        (append
        (list (jetpacs-row
               (jetpacs-with-attrs
                (jetpacs-text (format "Last %d lines"
                                      jetpacs-emacs-ui-messages-lines)
                              :style "caption")
                :weight 1)
               (jetpacs-button
                "Copy all"
                (jetpacs-clipboard-copy
                 (with-current-buffer buf
                   (buffer-substring-no-properties
                    (save-excursion
                      (goto-char (point-max))
                      (forward-line (- jetpacs-emacs-ui-messages-lines))
                      (point))
                    (point-max)))))
               :align "center"))
         (jetpacs-buffer-render-tail buf jetpacs-emacs-ui-messages-lines))))
     :back back)))

;; --- imenu -------------------------------------------------------------------

(defun jetpacs-emacs-ui-imenu-flatten (index)
  "Flatten imenu INDEX into a flat alist of (\"path / label\" . POS).
Handles both leaf shapes — (NAME . POS) and (NAME POS FN …) — and
recurses into submenus, joining the path with \" / \".  Drops
*Rescan*, dead markers, and positions before point-min; markers
dereference to integers."
  (let (out)
    (cl-labels
        ((flat (entries path)
           (dolist (e entries)
             (when (consp e)
               (let ((name (car e)) (tail (cdr e)))
                 (cond
                  ((and (stringp name) (equal name "*Rescan*")) nil)
                  ;; Leaf: (NAME . POS)
                  ((number-or-marker-p tail)
                   (push (cons (if path (concat path " / " name) name)
                               tail)
                         out))
                  ;; Leaf: (NAME POS FN …)
                  ((and (consp tail) (number-or-marker-p (car tail)))
                   (push (cons (if path (concat path " / " name) name)
                               (car tail))
                         out))
                  ;; Submenu: (NAME . ENTRIES)
                  ((listp tail)
                   (flat tail (if path (concat path " / " name) name)))))))))
      (flat index nil))
    (nreverse
     (delq nil
           (mapcar (lambda (cell)
                     (let ((pos (cdr cell)))
                       (cond
                        ((markerp pos)
                         (and (marker-buffer pos)
                              (cons (car cell) (marker-position pos))))
                        ((and (numberp pos) (>= pos 1)) cell)
                        (t nil))))
                   out)))))

(defun jetpacs-emacs-ui--imenu-flow (name)
  "The in-flow imenu picker for buffer NAME; prompts bridge from here."
  (let* ((buf (get-buffer name))
         (flat (and buf
                    (with-current-buffer buf
                      (jetpacs-emacs-ui-imenu-flatten
                       (condition-case nil
                           (imenu--make-index-alist t)
                         (error nil)))))))
    (if (not flat)
        (jetpacs-shell-notify "No imenu entries here"
                              jetpacs-emacs-ui-owner)
      (let ((choice (completing-read "Section: " flat nil t)))
        (when-let* ((pos (cdr (assoc choice flat))))
          ;; The slice runs to the next flattened entry, or the end.
          (let* ((next (car (sort (delq nil
                                        (mapcar (lambda (c)
                                                  (and (> (cdr c) pos)
                                                       (cdr c)))
                                                flat))
                                  #'<)))
                 (end (with-current-buffer buf
                        (or next (point-max))))
                 ;; The region view re-pushes THIS surface (the results
                 ;; actions bind the same variable around their effect).
                 (jetpacs-results-event-surface jetpacs-emacs-ui--surface))
            (jetpacs-results-show-region name pos end choice pos)))))))

;; --- M-x and the palette -----------------------------------------------------

(defun jetpacs-emacs-ui--mx-flow ()
  "The in-flow M-x: bridged picker over `obarray', shimmed execution.
`jetpacs-command-visible-p' + require-match make a suppressed command
unrunnable from this picker, not merely unsuggested."
  (let* ((choice (completing-read "M-x " obarray
                                  #'jetpacs-command-visible-p t))
         (cmd (intern-soft choice)))
    (when (commandp cmd)
      (let ((landed (jetpacs-buffer-call-shimmed
                     cmd
                     (lambda (err)
                       (jetpacs-shell-notify
                        (format "M-x %s: %s" choice (car err))
                        jetpacs-emacs-ui-owner)))))
        ;; If the command went somewhere, follow it there.
        (when-let* ((buf (car-safe landed)))
          (when (and (buffer-live-p buf)
                     (not (string-prefix-p " " (buffer-name buf))))
            (jetpacs-navigate-buffer buf jetpacs-emacs-ui--surface)))))))

(defun jetpacs-emacs-ui--palette-flow (name)
  "The in-flow command palette for buffer NAME."
  (when-let* ((buf (get-buffer name)))
    (let* ((cands (jetpacs-keymap-palette-candidates buf)))
      (if (null cands)
          (jetpacs-shell-notify "No commands to offer here"
                                jetpacs-emacs-ui-owner)
        (let* ((choice (completing-read "Command: " cands nil t))
               (target (cdr (assoc choice cands))))
          ;; NOT `execute-kbd-macro': the command loop it spins runs
          ;; against the SELECTED WINDOW's buffer, and the viewed buffer
          ;; is never in a window here — the key would self-insert into
          ;; *scratch* and clobber `current-buffer'.  (The poc shipped
          ;; exactly that; it survived only because on a desktop the
          ;; viewed buffer was also the selected window.)  Resolve the
          ;; binding in the buffer, then run the COMMAND under the JA-2
          ;; shims, which keep the buffer current and capture any jump.
          (with-current-buffer buf
            (let ((cmd (pcase target
                         (`(key . ,desc) (key-binding (kbd desc)))
                         (`(command . ,cmd) cmd))))
              (if (not (commandp cmd))
                  (message "jetpacs-emacs-ui: %S no longer runs anything"
                           target)
                (jetpacs-buffer-call-shimmed
                 cmd
                 (lambda (err)
                   (message "jetpacs-emacs-ui: %S failed: %s"
                            target (jetpacs--error-label err)))))))
          (jetpacs-buffer-defer-refresh jetpacs-emacs-ui--surface))))))

;; --- Live refresh ------------------------------------------------------------

(defcustom jetpacs-emacs-ui-live-refresh t
  "When non-nil, the drilled-in buffer re-pushes as it changes."
  :type 'boolean :group 'jetpacs)

(defcustom jetpacs-emacs-ui-live-interval 1.0
  "Seconds between change polls of the viewed buffer."
  :type 'number :group 'jetpacs)

(defvar jetpacs-emacs-ui--live-timer nil)
(defvar jetpacs-emacs-ui--live-buffer nil)
(defvar jetpacs-emacs-ui--live-tick nil)

(defun jetpacs-emacs-ui--top-buffer ()
  "The buffer NAME behind our stack's top screen, or nil."
  (gethash (car (jetpacs-chrome-stack jetpacs-emacs-ui-owner))
           jetpacs-emacs-ui--screens))

(defun jetpacs-emacs-ui--live-stop ()
  (when (timerp jetpacs-emacs-ui--live-timer)
    (cancel-timer jetpacs-emacs-ui--live-timer))
  (setq jetpacs-emacs-ui--live-timer nil
        jetpacs-emacs-ui--live-buffer nil
        jetpacs-emacs-ui--live-tick nil))

(defun jetpacs-emacs-ui--live-poll ()
  "Push when the watched buffer changed; stop when no longer relevant."
  (let ((buf (and jetpacs-emacs-ui--live-buffer
                  (get-buffer jetpacs-emacs-ui--live-buffer))))
    (if (not (and jetpacs-emacs-ui-live-refresh
                  buf
                  (jetpacs-connected-p)
                  (equal jetpacs-emacs-ui--live-buffer
                         (jetpacs-emacs-ui--top-buffer))))
        (jetpacs-emacs-ui--live-stop)
      (let ((tick (buffer-chars-modified-tick buf)))
        (when (and jetpacs-emacs-ui--live-tick
                   (/= tick jetpacs-emacs-ui--live-tick))
          (condition-case nil
              (jetpacs-shell-push jetpacs-emacs-ui-owner)
            (error nil))
          ;; Re-read AFTER the push: rendering *Messages* logs into
          ;; *Messages*, and reading the tick first would turn that
          ;; self-append into an endless refresh loop.
          (setq tick (buffer-chars-modified-tick buf)))
        (setq jetpacs-emacs-ui--live-tick tick)))))

(defun jetpacs-emacs-ui--reconcile-live-watch ()
  "After any push: watch our top screen's buffer, or stop.
On `jetpacs-shell-after-push-hook', which fires for EVERY surface's
push — the top-buffer check keys the watch to this app's own stack."
  (let ((name (and jetpacs-emacs-ui-live-refresh
                   (jetpacs-connected-p)
                   (jetpacs-emacs-ui--top-buffer))))
    (cond
     ((null name) (jetpacs-emacs-ui--live-stop))
     ((equal name jetpacs-emacs-ui--live-buffer) nil)
     (t (jetpacs-emacs-ui--live-stop)
        (when-let* ((buf (get-buffer name)))
          (setq jetpacs-emacs-ui--live-buffer name
                jetpacs-emacs-ui--live-tick (buffer-chars-modified-tick buf)
                jetpacs-emacs-ui--live-timer
                (run-at-time jetpacs-emacs-ui-live-interval
                             jetpacs-emacs-ui-live-interval
                             #'jetpacs-emacs-ui--live-poll)))))))

(add-hook 'jetpacs-shell-after-push-hook
          #'jetpacs-emacs-ui--reconcile-live-watch)

;; --- Actions -----------------------------------------------------------------

(with-jetpacs-owner jetpacs-emacs-ui-owner
  (jetpacs-chrome-define-root jetpacs-emacs-ui-owner "hub"
                              #'jetpacs-emacs-ui--hub-screen)

  (jetpacs-defaction "jetpacs.emacs.view"
    (lambda (args params)
      (let ((name (plist-get args :buffer)))
        (cond
         ((not (and (stringp name) (get-buffer name))) 'stale)
         ((jetpacs-event-stale-p params) 'stale)
         ((not (jetpacs-buffer-exposed-buffer-p name "jetpacs.emacs.view"))
          (message "jetpacs-emacs-ui: refused a view of a buffer never \
offered (SPEC 23.1)")
          'rejected)
         (t (jetpacs-flow-continue
             (lambda () (jetpacs-emacs-ui--push-buffer-screen name)))
            'accepted)))))

  (jetpacs-defaction "jetpacs.emacs.messages"
    (lambda (_args _params)
      (puthash "messages" "*Messages*" jetpacs-emacs-ui--screens)
      (jetpacs-flow-continue
       (lambda ()
         (condition-case err
             (jetpacs-chrome-push-screen jetpacs-emacs-ui-owner "messages"
                                         #'jetpacs-emacs-ui--messages-screen)
           (error (message "jetpacs-emacs-ui: messages push failed: %s"
                           (jetpacs--error-label err))))))
      'accepted))

  (jetpacs-defaction "jetpacs.emacs.mx"
    (lambda (_args _params)
      (jetpacs-flow-continue #'jetpacs-emacs-ui--mx-flow)
      'accepted))

  (jetpacs-defaction "jetpacs.emacs.imenu"
    (lambda (args params)
      (let ((name (plist-get args :buffer)))
        (cond
         ((not (and (stringp name) (get-buffer name))) 'stale)
         ((jetpacs-event-stale-p params) 'stale)
         ((not (jetpacs-buffer-exposed-buffer-p name "jetpacs.emacs.imenu"))
          'rejected)
         (t (jetpacs-flow-continue
             (lambda () (jetpacs-emacs-ui--imenu-flow name)))
            'accepted)))))

  (jetpacs-defaction "jetpacs.emacs.imenu-clear"
    (lambda (_args _params)
      (jetpacs-results-clear-region)
      (jetpacs-buffer-defer-refresh jetpacs-emacs-ui--surface)
      'accepted))

  (jetpacs-defaction "jetpacs.emacs.palette"
    (lambda (args params)
      (let ((name (plist-get args :buffer)))
        (cond
         ((not (and (stringp name) (get-buffer name))) 'stale)
         ((jetpacs-event-stale-p params) 'stale)
         ((not (jetpacs-buffer-exposed-buffer-p name "jetpacs.emacs.palette"))
          'rejected)
         (t (jetpacs-flow-continue
             (lambda () (jetpacs-emacs-ui--palette-flow name)))
            'accepted))))))

;; --- Teardown ----------------------------------------------------------------

(defun jetpacs-emacs-ui--on-teardown (owner)
  "Sweep this module's watch and screen registry with its owner."
  (when (equal owner jetpacs-emacs-ui-owner)
    (jetpacs-emacs-ui--live-stop)
    (clrhash jetpacs-emacs-ui--screens)))

(add-hook 'jetpacs-teardown-functions #'jetpacs-emacs-ui--on-teardown)

(defun jetpacs-emacs-ui-unload-function ()
  "Unload hygiene: hooks, the watch, the surface registration."
  (remove-hook 'jetpacs-shell-after-push-hook
               #'jetpacs-emacs-ui--reconcile-live-watch)
  (remove-hook 'jetpacs-teardown-functions #'jetpacs-emacs-ui--on-teardown)
  (jetpacs-emacs-ui--live-stop)
  (ignore-errors (jetpacs-teardown-owner jetpacs-emacs-ui-owner))
  nil)

(provide 'jetpacs-emacs-ui)
;;; jetpacs-emacs-ui.el ends here
