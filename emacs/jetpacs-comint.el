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
;; The input's widget id is STABLE — SPEC 13.6's draft reconciliation then
;; preserves half-typed text across background transcript pushes — and the
;; field clears through SPEC 17.4's `clear_on_submit', which clears only
;; once the occurrence is safely admitted.
;;
;; Rung JC-3c of docs/PLAN-jetpacs-consumers.md.
;;
;; Known gap: a password prompt raised from the process filter
;; (`comint-watch-for-password-prompt') while NO action handler is running
;; is not bridged to the phone — it blocks in the desktop minibuffer like
;; any other filter-time prompt.  What is closed as of JC-3's Phase A is
;; the dangerous half: that prompt reaching the inside of a dispatch
;; extent through `comint-send-input''s echo-wait loop.  See
;; `jetpacs-comint--send-input'.

;;; Code:

(require 'cl-lib)
(require 'comint)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-buffer)

(defcustom jetpacs-comint-tail-lines 200
  "Transcript lines rendered from the tail of a comint buffer."
  :type 'integer :group 'jetpacs)

(defun jetpacs-comint--input-id (name)
  "A stable SPEC 4.4 widget id for the input row of comint buffer NAME.

Every standard REPL buffer name is an INVALID identifier: the grammar is
`[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}' and `*shell*', `*ielm*',
`*Async Shell Command*' and `shell<2>' all carry `*', spaces, or
angle brackets.  `jetpacs-text-input' validates `:id', so a raw name
signalled and took the WHOLE render down — not just the widget — on
every REPL anyone actually uses.

Out-of-charset characters collapse to `-', a leading alnum is
guaranteed, and a sha1 of the ORIGINAL name is appended because
sanitizing is lossy: `*shell*' and `-shell-' would otherwise collide,
and a collision cross-seeds SPEC 13.6 input drafts between two REPLs.

STABLE across renders on purpose (see `jetpacs-comint-render').
The algorithm was promoted to `jetpacs-wire-id' (B5); this delegation
is byte-identical to the original for every NAME, so live SPEC 13.6
drafts survive the refactor."
  (jetpacs-wire-id "comint" name))

(defun jetpacs-comint--refresh (params)
  "Re-push the surface the event came from, deferred (SPEC 14.4/D1)."
  (jetpacs-buffer-defer-refresh (plist-get params :surface)))

;; --- Rendering ---------------------------------------------------------------

(defun jetpacs-comint-render (buf)
  "Tier-1 skin: comint BUF as status row + transcript tail + input row."
  (with-current-buffer buf
    (let* ((name (buffer-name))
           (proc (get-buffer-process buf))
           (live (and proc (process-live-p proc)))
           ;; SPEC 4.1: a process name comes from the command line and a
           ;; buffer name can hold anything the user typed; both reach node
           ;; text here, and an undecodable octet makes `json-serialize'
           ;; signal and takes the whole push down.
           (status (jetpacs-buffer-scalar-text
                    (if live
                        (format "%s — %s" (process-name proc)
                                (process-status proc))
                      "no live process")))
           (interrupt (and live
                           (jetpacs-action "comint.interrupt"
                                           :args (list :buffer name))))
           (status-row
            (apply #'jetpacs-row
                   (delq nil
                         (list (jetpacs-with-attrs
                                (jetpacs-box
                                 (jetpacs-text status :style "caption"))
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
           ;; It also calls `jetpacs-buffer-forget-exposed' for this buffer,
           ;; which is why the whole-buffer records below are written AFTER
           ;; it and not before.
           (tail (jetpacs-buffer-render-tail buf jetpacs-comint-tail-lines))
           (input
            (when live
              ;; The input row is the scroll target: it sits at the bottom
              ;; and every output line shifts its index, so the view follows
              ;; the transcript — the terminal "tail -f" feel.  `text_input'
              ;; is Core, so this needs no degrade.
              ;;
              ;; The id is STABLE and the field clears via SPEC 17.4's
              ;; `clear_on_submit'.  Rotating the id per send (the poc's
              ;; approach) cleared the field by minting a new widget, which
              ;; cleared it UNCONDITIONALLY — a send the Companion went on
              ;; to drop, reject, or time out ate the user's typing.  17.4
              ;; clears only once the occurrence is safely admitted and MUST
              ;; retain the value otherwise; and a stable id is what SPEC
              ;; 13.6 needs to preserve a half-typed draft across a
              ;; background transcript refresh — the other half of the same
              ;; problem.
              (list (jetpacs-with-attrs
                     (jetpacs-text-input
                      ;; The claim can SUFFIX this when the same buffer is
                      ;; rendered twice in one document (a hub view plus a
                      ;; drill) — the first claimant keeps the stable id
                      ;; and its SPEC 13.6 draft.
                      (jetpacs-claim-node-id (jetpacs-comint--input-id name))
                      :hint "Input — Enter sends"
                      :single-line t :monospace t :clear-on-submit t
                      :on-submit (jetpacs-action "comint.send"
                                                 :args (list :buffer name)))
                     :scroll_here t)))))
      ;; SPEC 23.1: record that this Emacs presented THIS buffer with these
      ;; affordances.  Both wire actions address the BUFFER rather than an
      ;; offset in it, so there is no per-position record to consult — and a
      ;; plain shell transcript exposes no positions at all, so borrowing
      ;; the position table would leave the gate empty for exactly the
      ;; common case.
      (jetpacs-buffer-expose-buffer name "comint.send")
      (jetpacs-buffer-expose-buffer name "comint.interrupt")
      (append (list status-row) tail input))))

(jetpacs-render-buffer-register 'comint-mode #'jetpacs-comint-render)

;; --- Actions -----------------------------------------------------------------

(defun jetpacs-comint--live-buffer (name action)
  "The comint buffer NAME when ACTION may address it, else nil.
The gate for both wire actions.  A name off the wire can only ever reach
the process of an already-open comint buffer (SPEC 23.2) that THIS Emacs
actually presented to the Companion with this affordance (SPEC 23.1) —
\"a live comint buffer exists\" is not the same claim as \"I offered you
this one\", and only the second is a trust boundary."
  (let ((buf (and (stringp name) (get-buffer name))))
    (and buf
         (with-current-buffer buf (derived-mode-p '(comint-mode)))
         (let ((proc (get-buffer-process buf)))
           (and proc (process-live-p proc)))
         (jetpacs-buffer-exposed-buffer-p name action)
         buf)))

(defun jetpacs-comint--send-input ()
  "Deliver the pending input in the current comint buffer, without wedging.

`comint-send-input' is neither prompt-free nor bounded, and both hazards
are in one branch (comint.el:2034-2049 in Emacs 30.1):

  (when (and comint-process-echoes (not artificial))
    ... (while (and ... (accept-process-output proc) ...)))

That `accept-process-output' RE-ENTERS the jsonrpc process filter from
inside the dispatch extent, and never returns if the process stops
echoing.  It also runs pending TIMERS — which is precisely how 30.1's
deliberately-deferred password prompt arrives: the process filter
`comint-watch-for-password-prompt' schedules `read-passwd' with
`run-at-time' 0 specifically so it does not block the filter, and this
loop then pulls it in anyway.

`comint-process-echoes' is buffer-local (comint.el:771) and set by gud,
idlw-shell, prolog, and per-buffer for ssh/telnet — so this is a live
configuration, not a theoretical one.  Binding it nil closes the whole
branch: no echo wait, no re-entrancy, no timer pump.

`jetpacs-with-no-prompts' is belt and braces over the rest of the input
path — `comint-input-filter-functions' (shell-directory-tracker does
TRAMP-capable file checks) and, under `comint-input-autoexpand',
`comint-replace-by-expanded-history'."
  (let ((comint-process-echoes nil))
    (jetpacs-with-no-prompts
      (comint-send-input))))

(jetpacs-defaction "comint.send"
  ;; SPEC 14.3: `on_submit' injects the submitted text as `value' into a
  ;; copy of the descriptor's args (only a PASSWORD submission uses
  ;; `fields'), so the input arrives in ARGS.
  ;;
  ;; `stale' is NOT consulted, deliberately: a REPL send is append-only
  ;; and indexes no snapshot offset, so an event created against an older
  ;; revision means exactly what it meant when it was typed.  (Contrast
  ;; `sections.visit', where a refresh moves every offset.)
  (lambda (args params)
    (let ((buf (jetpacs-comint--live-buffer (plist-get args :buffer)
                                            "comint.send"))
          (input (plist-get args :value)))
      (cond
       ;; No such buffer, wrong mode, no live process, or never presented:
       ;; nothing will ever make this event deliverable.
       ((null buf) 'rejected)
       ((not (stringp input)) 'rejected)
       (t
        ;; Synchronous, so `accepted' names input the process really got
        ;; (SPEC 14.4); a failure answers `rejected' rather than claiming
        ;; delivery.
        (with-current-buffer buf
          (goto-char (point-max))
          (insert input)
          (jetpacs-comint--send-input))
        (jetpacs-comint--refresh params)
        'accepted)))))

(jetpacs-defaction "comint.interrupt"
  ;; Also does not consult `stale' — a SIGINT to a running job is about
  ;; the process's present, not the snapshot it was tapped against.
  (lambda (args params)
    (let ((buf (jetpacs-comint--live-buffer (plist-get args :buffer)
                                            "comint.interrupt")))
      (if (null buf)
          'rejected
        ;; `comint-interrupt-subjob' is D2-bounded: `comint-skip-input'
        ;; binds `comint-input-sender' to `ignore' and passes ARTIFICIAL
        ;; non-nil, so the echo-wait branch is skipped entirely.
        (with-current-buffer buf
          (comint-interrupt-subjob))
        (jetpacs-comint--refresh params)
        'accepted))))

(provide 'jetpacs-comint)
;;; jetpacs-comint.el ends here
