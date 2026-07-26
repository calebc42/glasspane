;;; jetpacs-navigate.el --- The buffer-view host: any buffer as a drill-in -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JA-2 of docs/PLAN-jetpacs-apps.md (B4): the HOST that turns "run this
;; Emacs thing" into "a rendered buffer on the originating owner's
;; surface, with a way back".  Six poc modules each hand-rolled a slice
;; of this; the host is the substrate they all port onto (JA-3's buffer
;; list is its first real consumer — deliberately NOT in this rung).
;;
;; The shape: `jetpacs-buffer-funcall-shimmed' (the new thunk primitive
;; on the renderer) captures where a thunk went; the navigator renders
;; that buffer through the `jetpacs-render-buffer' dispatch seam (skins
;; are additive: a tabulated-list target drills into JC-2 cards) and
;; hands the screen to `jetpacs-navigate-drill-function' — the chrome
;; kit's stack, decoupled by a function seam exactly like
;; `jetpacs-buffer-refresh-function', so a missing host degrades to a
;; snackbar rather than a load failure.
;;
;; D1: the target surface resolves eagerly — explicit arg, else the
;; device-flow surface (which answers both inside a handler and inside
;; a flow continuation), else the owner default.  D2: from inside a
;; handler the thunk is deferred through `jetpacs-flow-continue' (the
;; no-prompts regime holds THROUGH timers pumped inside the extent, so
;; a run-at-time dodge would not help; the flow marker also lets any
;; prompt the thunk raises bridge to the device).

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-buffer)
(require 'jetpacs-shell)

(defvar jetpacs-navigate-drill-function nil
  "The screen-stack seam: nil, or (SURFACE BUILDER LABEL) -> non-nil.
SURFACE is a full D1 surface id; BUILDER is nullary and returns a LIST
of nodes (the skin contract); LABEL is DISPLAY TEXT — a buffer name,
NOT a SPEC 4.4 identifier: the implementation must not use it as a wire
id or node key (mint ids through `jetpacs-wire-id').  The
implementation MUST: mutate its per-surface stack synchronously (cheap,
dispatch-extent safe); DEFER the presenting push (`jetpacs-shell-push'
SIGNALS on gate failure, and a signal after the stack mutated would
answer rejected for an effect that happened); own the back affordance;
and wrap its root assembly in `jetpacs-buffer-with-budget' so the drill
body and the chrome share one SPEC 4.5 allowance.  Emit node ids
through `jetpacs-claim-node-id' — SPEC 16.1 scopes id uniqueness to the
whole DOCUMENT, and a screen stack rendered as one multi_view puts N
independently-built subtrees in one.  The chrome kit wires
this under `with-eval-after-load'; the navigator never names it.")

(defun jetpacs-navigate--screen-builder (name)
  "A nullary builder closing over buffer NAME (never the object —
that would pin a dead buffer).  Re-resolves liveness at every build, so
a deferred-refresh re-push re-renders the live buffer or degrades to a
caption; it never auto-pops — back stays the stack's.  Renders through
the `jetpacs-render-buffer' dispatch seam, which also rewrites the SPEC
23.1 exposure records that authorize taps inside the drill."
  (lambda ()
    (if-let* ((buf (get-buffer name)))
        (jetpacs-render-buffer buf)
      (list (jetpacs-text (format "Buffer %s no longer exists" name)
                          :style "caption")))))

(defun jetpacs-navigate-buffer (buffer-or-name &optional surface label)
  "Present BUFFER-OR-NAME as a drill-in on SURFACE; the tablist seam.
SURFACE defaults to the device-flow surface, else the owner default
\(D1).  Returns the target surface when the drill was presented, nil
otherwise — never signals: a broken host must not turn a handler's
answer into rejected."
  (let ((buf (get-buffer buffer-or-name)))
    (if (null buf)
        (progn (message "jetpacs-navigate: no such buffer") nil)
      (let ((target (or surface (jetpacs-flow-surface)
                        (jetpacs--default-surface))))
        (if (and (functionp jetpacs-navigate-drill-function)
                 (funcall jetpacs-navigate-drill-function
                          target
                          (jetpacs-navigate--screen-builder
                           (buffer-name buf))
                          (or label (buffer-name buf))))
            target
          (jetpacs-shell-notify "No navigation host")
          (message "jetpacs-navigate: no drill host for this surface")
          nil)))))

(defun jetpacs-navigate-thunk (thunk &optional surface label)
  "Run THUNK, capture the buffer it went to, and drill into it.
The rewrite of the poc's view-buffer-of helper.  SURFACE resolves
EAGERLY (the dispatch extent is gone when a timer fires).  Inside an
action handler the work defers through `jetpacs-flow-continue' — the
sections.menu precedent: scheduling the presentation keeps the reply
prompt, and the flow marker lets a prompting thunk bridge — and the
handler answers its own `accepted'; elsewhere it runs synchronously.
A thunk that goes nowhere snackbars \"Nothing to show\"; a thunk error
logs and snackbars its error SYMBOL only (SPEC 23.3 — the poc
snackbarred the full message; that is not ported)."
  (let* ((target (or surface (jetpacs-flow-surface)
                     (jetpacs--default-surface)))
         (work
          (lambda ()
            (let* ((caught nil)
                   (dest (with-temp-buffer
                           (jetpacs-buffer-funcall-shimmed
                            thunk (lambda (err) (setq caught err)))))
                   (temp-origin-p
                    (not (buffer-live-p (car dest)))))
              (cond
               (caught
                (message "jetpacs-navigate: thunk failed: %s"
                         (jetpacs--error-label caught))
                (jetpacs-shell-notify
                 (format "Failed: %s" (jetpacs--error-label caught)))
                nil)
               ;; The temp-buffer origin makes "stayed put" unambiguous:
               ;; only a thunk that went nowhere can land there (and the
               ;; temp buffer is dead by now, hence the liveness test).
               (temp-origin-p
                (jetpacs-shell-notify "Nothing to show")
                nil)
               (t (jetpacs-navigate-buffer (car dest) target label)))))))
    (if (jetpacs-in-action-p)
        (progn (jetpacs-flow-continue work) target)
      (funcall work))))

;; The tablist seam: 1-arg calls conform via the &optional params.
(defvar jetpacs-tablist-view-buffer-function)
(with-eval-after-load 'jetpacs-tablist
  (setq jetpacs-tablist-view-buffer-function #'jetpacs-navigate-buffer))

(provide 'jetpacs-navigate)
;;; jetpacs-navigate.el ends here
