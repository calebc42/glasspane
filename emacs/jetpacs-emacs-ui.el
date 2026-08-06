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
;; A HARD dependency, not an optional one: every prompting flow below
;; states that its prompt reaches the device, and that is only true
;; with the dialog advice installed.
(require 'jetpacs-dialog)

(defconst jetpacs-emacs-ui-owner "hub"
  "The surface hosting the general-client screens: the HUB itself.
Jetpacs IS Emacs (owner decision 2026-08-06) — there is no separate
\"Emacs\" app to open, so buffer drills, the Messages tail, and palette
results land on the home stack.  The host defines the hub root; this
module only pushes screens onto it.")

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
        (jetpacs-scalar-text (abbreviate-file-name buffer-file-name))
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
  "The hub's rows; records a SPEC 23.1 exposure per listed buffer.
Each buffer's records are dropped and re-made, so `authorized' tracks
`offered' rather than accumulating: without this a buffer that scrolls
past `jetpacs-emacs-ui-max-buffers', or is killed and its name reused,
keeps an authority nothing on screen still grants — the whole-buffer
analogue of the span rule `jetpacs-buffer--expose-node-taps' enforces."
  (mapcar
   (lambda (buf)
     (let ((name (buffer-name buf)))
       (jetpacs-buffer-forget-exposed name)
       (jetpacs-buffer-expose-buffer name "jetpacs.emacs.view")
       (jetpacs-chrome-row
        ;; SPEC 4.1: a buffer or file name can hold a raw-byte char
        ;; (#x3FFF80..#x3FFFFF) that `json-serialize' refuses.  The hub is
        ;; the REGISTERED ROOT, so an unsanitized name does not degrade to
        ;; one error card — it makes the whole surface unpushable for as
        ;; long as that buffer lives, and the user cannot reach the list to
        ;; kill it.  Every sibling emitter sanitizes; this one must too.
        (jetpacs-scalar-text
         (if (and (buffer-file-name buf) (buffer-modified-p buf))
             (concat "● " name)
           name))
        :subtitle (jetpacs-emacs-ui--buffer-subtitle buf)
        :on-tap (jetpacs-action "jetpacs.emacs.view"
                                :args (list :buffer name))
        :key (jetpacs-wire-id "buf" name))))
   (jetpacs-emacs-ui--listed-buffers)))

(defun jetpacs-emacs-ui--charge-rows (rows)
  "ROWS trimmed to what the shared SPEC 4.5 byte budget can carry.
The Tier-0 walk spends the byte budget honestly, but rows built OUTSIDE
it — this hub — were invisible to that accounting, so a drilled screen
below believed it owned the whole frame and the finished document blew
`max_frame_bytes'.  Nothing on the wire then renders at all: the gate
refuses the SurfaceSpec, so an over-long buffer list took the surface
down rather than truncating itself."
  (let ((left (cdr-safe jetpacs-buffer-budget))
        (kept nil)
        (dropped 0))
    (dolist (row rows)
      (cond
       ((null left) (push row kept))
       ((> left 0)
        (let ((size (jetpacs-buffer-node-bytes row)))
          (if (> size left)
              (setq dropped (1+ dropped) left 0)
            (setq left (- left size))
            (push row kept))))
       (t (setq dropped (1+ dropped)))))
    (when (and (consp jetpacs-buffer-budget) (cdr jetpacs-buffer-budget))
      (setcdr jetpacs-buffer-budget (max 0 left)))
    (nreverse
     (if (zerop dropped)
         kept
       (cons (jetpacs-text (format "… %d more buffer(s) (surface budget)"
                                   dropped)
                           :style "caption")
             kept)))))

(defun jetpacs-emacs-ui--hub-screen (back)
  "The root screen: Messages row, then every offerable buffer."
  (jetpacs-chrome-screen
   "Buffers"
   (apply #'jetpacs-lazy-column
          (jetpacs-emacs-ui--charge-rows
           (cons (jetpacs-chrome-row
                  "*Messages*"
                  :subtitle "the echo-area log"
                  :icon "description"
                  :on-tap (jetpacs-action "jetpacs.emacs.messages")
                  :key "row-messages")
                 (jetpacs-emacs-ui--hub-rows))))
   :back back
   :actions (list (jetpacs-emacs-ui-mx-button))))

(defun jetpacs-emacs-ui-mx-button ()
  "The top-bar M-x affordance any app may embed.
`jetpacs.emacs.mx' is a GLOBAL VERB (it reads no surface-bound
arguments), so the button works from any screen's top bar — the
docs/CHROME-VOCABULARY.md top-bar contract puts it top-right."
  (jetpacs-icon-button "terminal" (jetpacs-action "jetpacs.emacs.mx")
                       :content-description "M-x"))

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
         (jetpacs-scalar-text name)
         (jetpacs-empty-state :title "Buffer is gone") :back back)
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
         (jetpacs-scalar-text name) body
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

(defcustom jetpacs-emacs-ui-copy-max-bytes 4096
  "Byte cap on the *Messages* \"Copy all\" payload.
The rendered tail is already bounded by the SPEC 4.5 budget; this
descriptor is NOT (it is a second copy of the same text, invisible to
that accounting), so it carries its own bound."
  :type 'natnum :group 'jetpacs)

(defun jetpacs-emacs-ui--messages-copy-text (buf)
  "The clipboard payload for BUF's tail: sanitized and byte-capped."
  (let* ((raw (with-current-buffer buf
                (buffer-substring-no-properties
                 (save-excursion
                   (goto-char (point-max))
                   (forward-line (- jetpacs-emacs-ui-messages-lines))
                   (point))
                 (point-max))))
         (clean (jetpacs-scalar-text raw)))
    (if (<= (string-bytes clean) jetpacs-emacs-ui-copy-max-bytes)
        clean
      ;; Trim by CHARACTERS until the byte cap holds — a byte-wise
      ;; substring would split a multibyte char and reintroduce exactly
      ;; the unserializable value the sanitize just removed.
      (let ((n (length clean)))
        (while (and (> n 0)
                    (> (string-bytes (substring clean 0 n))
                       jetpacs-emacs-ui-copy-max-bytes))
          (setq n (/ (* n 9) 10)))
        (substring clean 0 n)))))

(defun jetpacs-emacs-ui--messages-screen (back)
  "The *Messages* tail over `jetpacs-buffer-render-tail'."
  (let ((buf (get-buffer "*Messages*")))
    (jetpacs-chrome-screen
     "*Messages*"
     (if (not buf)
         (jetpacs-empty-state :title "No messages yet")
       (apply #'jetpacs-column
        (append
        (list (apply
               #'jetpacs-row
               (append
                (list (jetpacs-with-attrs
                       (jetpacs-text (format "Last %d lines"
                                             jetpacs-emacs-ui-messages-lines)
                                     :style "caption")
                       :weight 1))
                ;; The copy affordance rides three disciplines the
                ;; `jetpacs-clip' exemplar established and this screen
                ;; must not skip: only offer it when the Companion
                ;; ADVERTISES the builtin (B13); sanitize (SPEC 4.1 —
                ;; *Messages* is the buffer most likely to carry a raw
                ;; octet, echoed from any process line); and CAP the
                ;; payload, which is otherwise a second full copy of the
                ;; tail riding invisibly past the SPEC 4.5 accounting
                ;; that only counts the rendered nodes.
                (when (jetpacs-builtin-advertised-p "clipboard.copy")
                  (list (jetpacs-button
                         "Copy all"
                         (jetpacs-clipboard-copy
                          (jetpacs-emacs-ui--messages-copy-text buf)))))
                (list :align "center"))))
         (jetpacs-buffer-render-tail buf jetpacs-emacs-ui-messages-lines))))
     :back back)))

(defun jetpacs-emacs-ui--with-prompting (fn)
  "Run FN only if a prompt raised now would reach the device.
Every flow here exists to ASK something.  Without a bridge the dialog
advice falls through to the real minibuffer — on a daemon or an
unattended desktop that is a prompt nobody can answer, with the device
already told `accepted'.  Refusing loudly beats wedging silently.

Also re-checked after the fact by each flow's own liveness guards: the
device round trip inside a prompt can take minutes, and a buffer named
before it may be gone after."
  (if (not (jetpacs-dialog-can-bridge-p))
      (jetpacs-shell-notify
       (if jetpacs-dialog--pending
           "Busy — finish the open dialog first"
         "Dialogs are not available in this session")
       jetpacs-emacs-ui-owner)
    (condition-case err
        (funcall fn)
      ;; SPEC 23.3: the SYMBOL only — a flow error must not put document
      ;; text on the wire, and it must not die unreported in a timer.
      (error (message "jetpacs-emacs-ui: flow failed: %s"
                      (jetpacs--error-label err))
             (jetpacs-shell-notify "That did not work"
                                   jetpacs-emacs-ui-owner)))))

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
         (flat (and (buffer-live-p buf)
                    (with-current-buffer buf
                      (jetpacs-emacs-ui-imenu-flatten
                       (condition-case nil
                           (imenu--make-index-alist t)
                         (error nil)))))))
    (if (not flat)
        (jetpacs-shell-notify "No imenu entries here"
                              jetpacs-emacs-ui-owner)
      (let ((choice (completing-read "Section: " flat nil t)))
        ;; The prompt was a device round trip — minutes, potentially.
        ;; Re-resolve: the buffer captured before it may be gone, and
        ;; `with-current-buffer' on a killed object signals.
        (setq buf (get-buffer name))
        (when-let* (((buffer-live-p buf))
                    (pos (cdr (assoc choice flat))))
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
unrunnable from this picker, not merely unsuggested.

The ORIGIN buffer is explicit.  `jetpacs-buffer-call-shimmed' runs the
command in whatever buffer is current and its docstring says so, but a
`jetpacs-flow-continue' timer inherits whatever buffer the pump
happened to be in — so M-x ran somewhere arbitrary and the \"follow it
there\" check compared against that accident.  On a drilled screen the
origin is the buffer on screen, which is what the user means by
\"here\"; on the hub no buffer is named, so a scratch origin makes
`stayed put' detectable without mutating a real buffer by accident."
  (let* ((choice (completing-read "M-x " obarray
                                  #'jetpacs-command-visible-p t))
         (cmd (intern-soft choice))
         (top (jetpacs-emacs-ui--top-buffer))
         (origin (and top (get-buffer top))))
    (when (commandp cmd)
      (let* ((failed nil)
             (run (lambda ()
                    (jetpacs-buffer-call-shimmed
                     cmd
                     (lambda (err)
                       (setq failed t)
                       (jetpacs-shell-notify
                        (format "M-x %s: %s" choice
                                (jetpacs--error-label err))
                        jetpacs-emacs-ui-owner)))))
             (landed (if (buffer-live-p origin)
                         (with-current-buffer origin (funcall run))
                       (with-temp-buffer (funcall run)))))
        ;; Follow the command only when it actually went somewhere ELSE.
        ;; `call-shimmed' always reports a buffer — it returns the origin
        ;; when the command stayed put — so an unconditional drill sent
        ;; the user to a screen for the buffer they were already on, or
        ;; for a temp buffer that no longer exists.
        (let ((buf (car-safe landed)))
          (when (and (not failed)
                     (buffer-live-p buf)
                     (not (eq buf origin))
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
            ;; Run the command the row LABELLED.  Re-resolving the key
            ;; description here let the two diverge — char-property
            ;; keymaps that extraction never walked, and any rebinding
            ;; between render and tap.
            (let ((cmd (pcase target
                         (`(key ,cmd . ,_desc) cmd)
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

(defcustom jetpacs-emacs-ui-live-max-failures 3
  "Consecutive failed live pushes before the watch gives up.
The tick re-read after a push absorbs what the push logged
SYNCHRONOUSLY, but `surface.update' concludes asynchronously — a
failure logged from its callback lands in *Messages* after the
snapshot, and when *Messages* is the watched buffer that is a 1 Hz
self-sustaining loop.  A bound is the honest guard: the tick trick
cannot see a message that has not been written yet."
  :type 'natnum :group 'jetpacs)

(defvar jetpacs-emacs-ui--live-failures 0)
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
        jetpacs-emacs-ui--live-tick nil
        jetpacs-emacs-ui--live-failures 0))

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
          (if (condition-case nil
                  (progn (jetpacs-shell-push jetpacs-emacs-ui-owner) t)
                (error nil))
              (setq jetpacs-emacs-ui--live-failures 0)
            (setq jetpacs-emacs-ui--live-failures
                  (1+ jetpacs-emacs-ui--live-failures))
            (when (>= jetpacs-emacs-ui--live-failures
                      jetpacs-emacs-ui-live-max-failures)
              (message "jetpacs-emacs-ui: live refresh stopped after %d \
failed pushes" jetpacs-emacs-ui--live-failures)
              (jetpacs-emacs-ui--live-stop)))
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
  ;; No root of its own: the HOST defines the hub root, and the former
  ;; standalone "Emacs" hub survives as the Buffers screen, one drill
  ;; down on the home stack.
  (jetpacs-defaction "jetpacs.emacs.buffers"
    (lambda (_args _params)
      (jetpacs-flow-continue
       (lambda ()
         (condition-case err
             (jetpacs-chrome-push-screen jetpacs-emacs-ui-owner "buffers"
                                         #'jetpacs-emacs-ui--hub-screen)
           (error (message "jetpacs-emacs-ui: buffers push failed: %s"
                           (jetpacs--error-label err))))))
      'accepted)
    :any-surface t)

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
    ;; A GLOBAL VERB (the theme-toggle precedent):
    ;; `jetpacs-emacs-ui-mx-button' renders in other owners' top bars,
    ;; so the event's surface is legitimately foreign.  Safe under the
    ;; exemption: the handler reads no event arguments, and the flow's
    ;; origin falls back to scratch when this owner's stack holds no
    ;; drilled buffer.
    (lambda (_args _params)
      (jetpacs-flow-continue
       (lambda ()
         (jetpacs-emacs-ui--with-prompting #'jetpacs-emacs-ui--mx-flow)))
      'accepted)
    :any-surface t)

  (jetpacs-defaction "jetpacs.emacs.imenu"
    (lambda (args params)
      (let ((name (plist-get args :buffer)))
        (cond
         ((not (and (stringp name) (get-buffer name))) 'stale)
         ((jetpacs-event-stale-p params) 'stale)
         ((not (jetpacs-buffer-exposed-buffer-p name "jetpacs.emacs.imenu"))
          'rejected)
         (t (jetpacs-flow-continue
             (lambda ()
               (jetpacs-emacs-ui--with-prompting
                (lambda () (jetpacs-emacs-ui--imenu-flow name)))))
            'accepted)))))

  (jetpacs-defaction "jetpacs.emacs.imenu-clear"
    (lambda (_args _params)
      ;; The region view is SHARED state (results, sections and this
      ;; module all arm it).  Clear it only when it addresses the buffer
      ;; on our own top screen — otherwise this affordance silently
      ;; discards a grep/xref slice another surface is presenting.
      (let ((top (jetpacs-emacs-ui--top-buffer)))
        (if (and top (equal top (jetpacs-results-region-buffer)))
            (progn (jetpacs-results-clear-region)
                   (jetpacs-buffer-defer-refresh jetpacs-emacs-ui--surface)
                   'accepted)
          'stale))))

  (jetpacs-defaction "jetpacs.emacs.palette"
    (lambda (args params)
      (let ((name (plist-get args :buffer)))
        (cond
         ((not (and (stringp name) (get-buffer name))) 'stale)
         ((jetpacs-event-stale-p params) 'stale)
         ((not (jetpacs-buffer-exposed-buffer-p name "jetpacs.emacs.palette"))
          'rejected)
         (t (jetpacs-flow-continue
             (lambda ()
               (jetpacs-emacs-ui--with-prompting
                (lambda () (jetpacs-emacs-ui--palette-flow name)))))
            'accepted))))))

;; --- Teardown ----------------------------------------------------------------

(defun jetpacs-emacs-ui--on-kill-buffer ()
  "Revoke a dying buffer's SPEC 23.1 authority and forget its screen.
A record must not outlive the thing it authorized: buffer NAMES are
reused (`*grep*', `*shell*'), so a stale grant would silently authorize
a verb on a DIFFERENT buffer that happens to take the name."
  (when-let* ((name (buffer-name)))
    (jetpacs-buffer-forget-exposed name)
    (let (dead)
      (maphash (lambda (id b) (when (equal b name) (push id dead)))
               jetpacs-emacs-ui--screens)
      ;; Keep an id the chrome stack still holds: the screen degrades to
      ;; its own "Buffer is gone" card, which is the honest render.
      (let ((live (jetpacs-chrome-stack jetpacs-emacs-ui-owner)))
        (dolist (id dead)
          (unless (member id live)
            (remhash id jetpacs-emacs-ui--screens)))))))

(add-hook 'kill-buffer-hook #'jetpacs-emacs-ui--on-kill-buffer)

(defun jetpacs-emacs-ui-visit-region (name beg end label &optional point)
  "Arm the region view for NAME and DRILL to that buffer's screen.
The default seam only arms the region and re-pushes the CURRENT
surface, which shows the slice solely if a screen for the destination
buffer already happens to be on the stack — so a `results.visit' from
the general client landed nowhere at all.  Pushing the destination's
screen is what makes the tap mean something.

The push is DEFERRED because the seam runs inside the `results.visit'
dispatch extent, where `jetpacs-chrome-push-screen' signalling would
answer `rejected' for a jump that already happened."
  (jetpacs-results-show-region name beg end label point)
  (jetpacs-buffer-expose-buffer name "jetpacs.emacs.view")
  (run-at-time
   0 nil
   (lambda ()
     (unless (equal (jetpacs-emacs-ui--top-buffer) name)
       (jetpacs-emacs-ui--push-buffer-screen name)))))

;; Claim the seam only when it is still the DEFAULT — the "free or
;; already ours" guard `jetpacs-chrome--claim-drill-host' uses.  A bare
;; `unless' cannot work here: unlike the nil-sentinel seams, this one
;; ships pointing at `jetpacs-results-show-region', so an unguarded
;; claim would clobber a Tier-1's own visitor by load order.
(when (memq jetpacs-results-visit-region-function
            (list #'jetpacs-results-show-region
                  #'jetpacs-emacs-ui-visit-region))
  (setq jetpacs-results-visit-region-function
        #'jetpacs-emacs-ui-visit-region))

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
  (remove-hook 'kill-buffer-hook #'jetpacs-emacs-ui--on-kill-buffer)
  (jetpacs-emacs-ui--live-stop)
  (ignore-errors (jetpacs-teardown-owner jetpacs-emacs-ui-owner))
  nil)

(provide 'jetpacs-emacs-ui)
;;; jetpacs-emacs-ui.el ends here
