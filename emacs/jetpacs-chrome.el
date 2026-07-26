;;; jetpacs-chrome.el --- Chrome kit + per-surface screen stack -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JA-2 of docs/PLAN-jetpacs-apps.md (B6, reduced): composition over the
;; smoke-verified scaffold/multi_view/view.switched machinery — not a
;; framework.  `jetpacs-chrome-screen' is a titled scaffold with an
;; optional back arrow; `jetpacs-chrome-row' is the hub list-row the poc
;; screens all shared; the per-surface SCREEN STACK renders as ONE
;; multi_view surface whose views are the stacked screens (decision:
;; representation A — back is then the `view.switch' BUILTIN,
;; companion-local, zero-latency, works offline, REQUIRED in every app
;; profile; and SPEC 13.4's preserve-current-view rule applies for
;; free: background refreshes omit `current_view' and never yank the
;; user; only push/pop/reset name one).
;;
;; Stack↔device sync rides `jetpacs-shell-view-change-functions' — the
;; shell's own view.switched registration; the kit must NEVER
;; `jetpacs-defaction' that name (it would REPLACE the shell's global
;; handler).  A back-arrow tap truncates the Emacs stack silently: the
;; device already shows the right screen, dead upper views leave the
;; snapshot at the next natural push.  Offline back drift is BENIGN by
;; design — do not "fix" it by forcing current_view on reconnect.
;;
;; Snackbar note (H10): `jetpacs-shell-push' injects a queued snackbar
;; only into a scaffold ROOT; a multi-view spec has no :t, so
;; `jetpacs-shell-notify' on a stack surface degrades to the gated
;; toast.  Extending the shell to inject into the current view's
;; scaffold is out of scope here.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-buffer)
(require 'jetpacs-shell)

(defvar jetpacs-chrome--stacks (make-hash-table :test #'equal)
  "SURFACE id -> screen stack, a list of (ID . BUILDER), TOP FIRST.
BUILDER takes one argument BACK — a `view.switch' descriptor, or nil at
the stack bottom — and returns a root Node.")

;;;; Composition

(cl-defun jetpacs-chrome-screen (title body &key back actions fab drawer
                                       on-refresh)
  "A titled scaffold screen.  BACK, when given, is the tap descriptor
of a leading arrow_back button (canonically `jetpacs-view-switch' of
the screen below).  The weight-1 title is what keeps trailing ACTIONS
at intrinsic width — the poc flex-trap lesson.  Validation rides the
builders: bad TITLE signals in `jetpacs-text', bad slots in
`jetpacs-scaffold', a bad BACK in `jetpacs-icon-button'."
  (jetpacs-scaffold
   :top-bar (apply #'jetpacs-row
                   (append
                    (when back
                      (list (jetpacs-icon-button "arrow_back" back
                                                 :content-description "back")))
                    (list (jetpacs-with-attrs
                           (jetpacs-text title :style "title")
                           :weight 1))
                    actions
                    (list :align "center" :spacing 4)))
   :body body :fab fab :drawer drawer :on-refresh on-refresh))

(cl-defun jetpacs-chrome-row (title &key subtitle icon leading trailing
                                    on-tap on-long-tap key)
  "The hub list-row: card > row > [leading, weighted column, trailing].
TITLE/SUBTITLE are strings; ICON is a convenience when LEADING is nil;
TRAILING is one node or a list.  KEY (a SPEC 4.4 identifier) rides
`jetpacs-with-attrs' — like :weight, it is a universal attr the
container builders silently DROP as a trailing option, the exact poc
bug this port fixes."
  (let* ((middle (jetpacs-with-attrs
                  (apply #'jetpacs-column
                         (append (list (jetpacs-text title))
                                 (when subtitle
                                   (list (jetpacs-text subtitle
                                                       :style "caption")))
                                 (list :spacing 2)))
                  :weight 1))
         (lead (or leading (and icon (jetpacs-icon icon))))
         (trail (cond ((null trailing) nil)
                      ((jetpacs--root-node-p trailing) (list trailing))
                      (t trailing)))
         (card (jetpacs-card
                (list (apply #'jetpacs-row
                             (append (when lead (list lead))
                                     (list middle)
                                     trail
                                     (list :align "center" :spacing 12))))
                :on-tap on-tap :on-long-tap on-long-tap)))
    (if key (jetpacs-with-attrs card :key key) card)))

;;;; The per-surface screen stack (representation A: one multi_view)

(defun jetpacs-chrome--build (surface)
  "The registered root builder: the stack as one multi_view.
Walks bottom-first so each screen's BACK targets the one below it;
`initial_view' is the stack TOP, so SPEC 13.4's new-surface and
vanished-view fallbacks land where Emacs believes the user is.  Signals
on an empty/missing stack — the shell degrades that to its error spec,
never the whole push."
  (let ((stack (gethash surface jetpacs-chrome--stacks)))
    (unless stack
      (error "jetpacs-chrome: no chrome stack for %s" surface))
    (let (views prev-id)
      (dolist (entry (reverse stack))
        (push (cons (car entry)
                    (funcall (cdr entry)
                             (and prev-id (jetpacs-view-switch prev-id))))
              views)
        (setq prev-id (car entry)))
      (jetpacs-multi-view (nreverse views) (caar stack)))))

(cl-defun jetpacs-chrome-define-root (surface-or-owner id builder
                                                       &key required)
  "Define SURFACE's chrome root screen; re-evaluation RESETS the stack.
Call under `with-jetpacs-owner' — the shell records the owner and
re-binds it around every build.  Returns the surface id."
  (let ((surface (jetpacs-shell--resolve-surface surface-or-owner)))
    (jetpacs--check-identifier id "screen id")
    (puthash surface (list (cons id builder)) jetpacs-chrome--stacks)
    (jetpacs-shell-define-root surface
                               (lambda () (jetpacs-chrome--build surface))
                               :required required)
    surface))

(defun jetpacs-chrome--stack-insert (surface id builder)
  "Validate and insert (ID . BUILDER) at SURFACE's stack top.
An ID already on the stack TRUNCATES to that entry and replaces its
builder — re-entrant navigation; without this `jetpacs-multi-view'
signals a duplicate view id and the surface degrades to the error
screen.  Pure stack mutation: no push."
  (let ((stack (gethash surface jetpacs-chrome--stacks)))
    (unless stack
      (error "jetpacs-chrome: no chrome stack for %s" surface))
    (jetpacs--check-identifier id "screen id")
    (let ((tail (cl-member id stack :key #'car :test #'equal)))
      (if tail
          (progn (setcdr (car tail) builder)
                 (puthash surface tail jetpacs-chrome--stacks))
        (puthash surface (cons (cons id builder) stack)
                 jetpacs-chrome--stacks)))))

(defun jetpacs-chrome-push-screen (surface-or-owner id builder)
  "Push screen ID onto SURFACE's stack and navigate to it.
ID is a SPEC 4.4 identifier, validated BEFORE any mutation — mint
dynamic ids from buffer names/paths through `jetpacs-wire-id'.  The
only navigation-forcing push shape (`:current-view').  From an action
handler pass (plist-get params :surface): the owner binding is nil in
a dispatch extent and the default would clobber another owner (D1).
Returns the claimed revision, or nil (disconnected, or the W10 ceiling
refused) — nil is NOT failure: the stack mutation is kept and the next
successful push renders it.  Never retry-loop on nil."
  (let ((surface (jetpacs-shell--resolve-surface surface-or-owner)))
    (jetpacs-chrome--stack-insert surface id builder)
    (jetpacs-shell-push surface :current-view id)))

(defun jetpacs-chrome-pop-screen (surface-or-owner)
  "Pop SURFACE's stack and navigate to the screen below (Emacs-side
back — a completed flow returning to its hub; the on-screen arrow never
calls this).  At the root: idempotent no-op returning nil."
  (let* ((surface (jetpacs-shell--resolve-surface surface-or-owner))
         (stack (gethash surface jetpacs-chrome--stacks)))
    (when (cdr stack)
      (puthash surface (cdr stack) jetpacs-chrome--stacks)
      (jetpacs-shell-push surface :current-view (caar (cdr stack))))))

(defun jetpacs-chrome-reset-screens (surface-or-owner)
  "Truncate SURFACE's stack to its root and navigate there.
Keeps the root cons, so the registered builder survives; the push
doubles as a hub refresh."
  (let* ((surface (jetpacs-shell--resolve-surface surface-or-owner))
         (stack (gethash surface jetpacs-chrome--stacks)))
    (when stack
      (let ((root (last stack)))
        (puthash surface root jetpacs-chrome--stacks)
        (jetpacs-shell-push surface :current-view (caar root))))))

(defun jetpacs-chrome-stack (surface-or-owner)
  "SURFACE's screen ids, top first, or nil (read-only)."
  (mapcar #'car (gethash (jetpacs-shell--resolve-surface surface-or-owner)
                         jetpacs-chrome--stacks)))

(defun jetpacs-chrome-remove (surface-or-owner)
  "Drop SURFACE's stack and tombstone the surface."
  (let ((surface (jetpacs-shell--resolve-surface surface-or-owner)))
    (remhash surface jetpacs-chrome--stacks)
    (jetpacs-shell-remove-root surface)))

;;;; Stack <-> device sync (the shell's view.switched, subscribed)

(defun jetpacs-chrome--on-view-switched (surface view)
  "Truncate SURFACE's stack to VIEW (a Companion-local back).
Runs INSIDE the dispatch extent under the no-prompts regime, so it is
two when-lets and nothing else — an error here would flip the whole
view.switched reply to rejected.  NO push: the device already shows the
right screen; dead upper views leave the snapshot at the next natural
push."
  (when-let* ((stack (gethash surface jetpacs-chrome--stacks)))
    (when-let* ((tail (cl-member view stack :key #'car :test #'equal)))
      (puthash surface tail jetpacs-chrome--stacks))))

(add-hook 'jetpacs-shell-view-change-functions
          #'jetpacs-chrome--on-view-switched)

;;;; The navigate drill seam (integration C7) and teardown (C8)

(defun jetpacs-chrome--drill (surface builder label)
  "The `jetpacs-navigate-drill-function' implementation.
LABEL is display text (a hostile buffer name) — the wire id is minted
\(B5), so an identical LABEL mints an identical id and the stack-insert
truncate-and-replace gives repeat-drill replace-top semantics for free.
The presenting push is DEFERRED: `jetpacs-shell-push' signals on gate
failure, and a synchronous signal inside a handler after the stack
mutated would answer rejected for an effect that happened."
  (let ((id (jetpacs-wire-id "drill" label)))
    (jetpacs-chrome--stack-insert
     surface id
     (lambda (back)
       (jetpacs-buffer-with-budget
         (jetpacs-chrome-screen
          label
          (apply #'jetpacs-column (funcall builder))
          :back back))))
    (run-at-time 0 nil
                 (lambda ()
                   (condition-case err
                       (jetpacs-shell-push surface :current-view id)
                     (error (message "jetpacs-chrome: drill push failed: %s"
                                     (jetpacs--error-label err))))))
    t))

(defvar jetpacs-navigate-drill-function)
(with-eval-after-load 'jetpacs-navigate
  (setq jetpacs-navigate-drill-function #'jetpacs-chrome--drill))

(defun jetpacs-chrome--on-teardown (owner)
  "Drop OWNER's stacks (JA-2 teardown hook) — stacks ONLY:
`jetpacs-teardown-owner' already tombstones via remove-root, so calling
`jetpacs-chrome-remove' here would double-tombstone."
  (dolist (surface (jetpacs-shell--owner-surfaces owner))
    (remhash surface jetpacs-chrome--stacks)))

(add-hook 'jetpacs-teardown-functions #'jetpacs-chrome--on-teardown)

(provide 'jetpacs-chrome)
;;; jetpacs-chrome.el ends here
