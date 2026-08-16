;;; glasspane-table.el --- Glasspane org-table/babel actions -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The G6 table rung (docs/PLAN-glasspane-app.md): the org-table
;; structure and cell editors, and the babel play verb.  The base
;; render's native-table upgrade is read-only (FOUNDATION-GAPS #11),
;; so this file also AUTHORS the app's tappable table node
;; (`glasspane-table-node'), whose cell descriptors ride the SPEC 23.1
;; exposure route — v1 baked real file paths and positions into the
;; wire args; no v3 descriptor may (S5).
;;
;; Retired against v1 (the plan's retirement list + G6 section):
;;
;; - org.footnote.show (v1 table:7-17): the base `jetpacs.org.footnote'
;;   (jetpacs-org-dialogs.el) owns the tapped-marker surface.
;; - The Appearance section's `jetpacs-dialog-style' row (v1 table:54):
;;   no such defcustom exists — dialog style is per-dialog (S3).
;; - The schema-driven org settings sections this rung used to register
;;   are FOUNDATION content now (emacs/jetpacs-org-settings.el, the
;;   ratified relocation of PLAN-jetpacs-debt-and-scaffold §3): every
;;   symbol in them was a built-in or foundation defcustom.  The one
;;   app-opinion row, `glasspane-babel-timeout', stays with the app —
;;   registered in glasspane-ui's own section beside the defcustom.
;;
;; The prompting arms (cell edit, the row/column menu, babel's
;; confirm) are the rung's D2 rewrite: the v1 handlers blocked the
;; dispatch on `read-string'/`completing-read'; here the handler
;; answers `accepted' on the strength of a `jetpacs-flow-begin'
;; continuation, and the prompt raised THERE bridges through the
;; jetpacs-dialog advice — behind `jetpacs-dialog-can-bridge-p', with
;; the headless refusal notifying instead of wedging a minibuffer
;; nobody attends (the JA-6 P2 lesson).

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-table)
(require 'ob-core)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-apps)
(require 'jetpacs-buffer)
(require 'jetpacs-dialog)
(require 'glasspane-org)
(require 'glasspane-ui)                 ; glasspane-babel-timeout

;;;; The exposure gate (SPEC 23.1 — the jetpacs-org-dialogs tap order)

(defun glasspane-table--cell-gate (args params verb)
  "Validate ARGS' exposure descriptor for VERB; (BUFFER . POS) or a status.
The shared front of every table/babel handler, in the base dialog-tap
gate order: malformed or unexposed addressing answers `rejected' (a
dead buffer included — the exposure died with the render that made
it), an event against an outdated snapshot `stale'.  POS tolerates the
JSON round trip's trailing .0."
  (let* ((name (plist-get args :buffer))
         (pos (plist-get args :pos))
         (buf (and (stringp name) (get-buffer name))))
    (when (numberp pos) (setq pos (truncate pos)))
    (cond
     ((not (and buf (integerp pos))) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-buffer-exposed-p name pos verb)) 'rejected)
     (t (cons buf pos)))))

(defun glasspane-table--flow-surface (params)
  "The surface a prompting flow bridges and repushes on.
A table tap always rides a real screen, but a queued replay may arrive
without `:surface' — fall through to the app's own."
  (or (plist-get params :surface)
      (jetpacs-shell-surface-for "glasspane")))

(defun glasspane-table--with-prompting (fn surface refusal)
  "Run FN only if a prompt raised now would reach the device.
The jetpacs-org-dialogs shape: with no bridge the advised prompt falls
through to a minibuffer nobody attends, so refusing loudly (REFUSAL to
SURFACE) beats wedging silently — and a flow error surfaces as a
SPEC 23.3 symbol, never text."
  (if (not (jetpacs-dialog-can-bridge-p))
      (jetpacs-shell-notify
       (if (bound-and-true-p jetpacs-dialog--pending)
           "Busy — finish the open dialog first"
         refusal)
       surface)
    (condition-case err
        (funcall fn)
      (error (message "glasspane: table flow failed: %s"
                      (jetpacs-error-label err))
             (jetpacs-shell-notify "That table edit did not work"
                                   surface)))))

;;;; The mutation funnel

(defun glasspane-table--mutate (buffer pos fn)
  "Run FN with point at POS inside BUFFER's table, then align and save.
FN performs one table mutation.  Afterwards the table is realigned,
recalculated when a #+TBLFM line follows it (formulas live Emacs-side —
the phone never computes), and saved through the app's synchronous
funnel so `accepted' means on-disk.  A mutation that moves point off
the table (killing a row) realigns from the table's start; one that
consumes the table entirely (killing its only row) skips the realign
instead of erroring.  The repush stays with the caller: the handler
arms defer it past the dispatch extent (D2), the prompting arms push
from their own flow."
  (with-current-buffer buffer
    (org-with-wide-buffer
     (goto-char pos)
     (unless (org-at-table-p) (error "No table at position %s" pos))
     (let ((table-beg (org-table-begin)))
       (funcall fn)
       (unless (org-at-table-p)
         (goto-char (min table-beg (point-max))))
       (when (org-at-table-p)
         (org-table-align)
         (when (save-excursion
                 (goto-char (org-table-end))
                 ;; "#+tblfm:" is valid org — match case-insensitively.
                 (let ((case-fold-search t))
                   (looking-at-p "[ \t]*#\\+TBLFM:")))
           (org-table-recalculate t)))))
    (glasspane-org-save-and-invalidate)))

(defun glasspane-table--clean-field (input)
  "INPUT flattened to one table field.
A field is one line between pipes — keep it that way."
  (string-replace "|" "\\vert{}" (string-replace "\n" " " input)))

;;;; The prompting flows (run inside `jetpacs-flow-begin', never dispatch)

(defun glasspane-table--edit-run (buffer pos surface)
  "The bridged cell editor: prefill, prompt, write back, repush.
A field that #+TBLFM computes opens its formula instead — recalculation
would immediately overwrite any value typed into it."
  (glasspane-table--with-prompting
   (lambda ()
     (let (current formula)
       (with-current-buffer buffer
         (org-with-wide-buffer
          (goto-char pos)
          (unless (org-at-table-p) (error "No table cell here"))
          (setq formula (ebp-org-table-field-formula))
          (unless formula
            (setq current (string-trim (org-table-get-field))))))
       (if formula
           (let ((input (string-trim
                         (read-string (format "Formula %s= " (car formula))
                                      (cdr formula)))))
             (if (string-empty-p input)
                 ;; A deliberate refusal notifies its own text; only
                 ;; unexpected errors take the generic 23.3 arm.
                 (jetpacs-shell-notify
                  "Empty formula — edit the #+TBLFM line to remove one"
                  surface)
               (glasspane-table--mutate
                buffer pos
                (lambda ()
                  (let* ((stored (org-table-get-stored-formulas t))
                         ;; The resolver returns the LHS exactly as
                         ;; written, so `assoc' finds it to update in
                         ;; place.
                         (entry (or (assoc (car formula) stored)
                                    (error "Formula no longer stored"))))
                    (setcdr entry input)
                    (save-excursion
                      (org-table-store-formulas stored)))))
               (ignore-errors (jetpacs-shell-push surface))))
         (let* ((input (read-string "Cell: " current))
                (new (glasspane-table--clean-field input)))
           (glasspane-table--mutate buffer pos
                                    (lambda ()
                                      (org-table-get-field nil new)))
           (ignore-errors (jetpacs-shell-push surface))))))
   surface
   "Cell editing needs an attended session"))

(defconst glasspane-table--menu-ops
  '(("Insert row above"   . org-table-insert-row)
    ("Insert column left" . org-table-insert-column)
    ("Delete row"         . org-table-kill-row)
    ("Delete column"      . org-table-delete-column))
  "The bridged structure edits.  Org's own commands fix up #+TBLFM
references (or mark them INVALID) on the way through.")

(defun glasspane-table--cell-menu-run (buffer pos surface)
  "The bridged row/column structure menu for the cell at POS."
  (glasspane-table--with-prompting
   (lambda ()
     (let* ((choice (completing-read "Row/column: "
                                     (mapcar #'car glasspane-table--menu-ops)
                                     nil t))
            (op (cdr (assoc choice glasspane-table--menu-ops))))
       (when op
         (glasspane-table--mutate buffer pos op)
         (ignore-errors (jetpacs-shell-push surface)))))
   surface
   "Table editing needs an attended session"))

(define-error 'glasspane-table--timeout "Babel run timed out")
(define-error 'glasspane-table--disabled
              "Babel evaluation disabled for this block")

(defconst glasspane-table--babel-refusal
  "Babel needs an attended session to confirm"
  "The headless refusal when a babel confirm prompt cannot bridge.")

(defun glasspane-table--babel-run (buffer pos surface)
  "Execute the src block at POS — inside a device flow, off the dispatch.
`org-confirm-babel-evaluate' is honored: the yes/no prompt bridges to a
native dialog, and it runs BEFORE the timeout starts so a slow answer
never counts against the execution budget.  The bridge check keys on
what the block actually demands (`org-babel-check-confirm-evaluate' —
a `:eval query' header prompts even with the global option nil), so a
confirm that cannot reach the device refuses instead of wedging."
  (condition-case err
      (progn
        (with-current-buffer buffer
          (org-with-wide-buffer
           (goto-char pos)
           (let ((info (org-babel-get-src-block-info)))
             (unless info (error "No source block here"))
             (when (and (eq (org-babel-check-confirm-evaluate info) 'query)
                        (not (jetpacs-dialog-can-bridge-p)))
               (signal 'inhibited-interaction nil))
             ;; `org-babel-confirm-evaluate' RETURNS nil on refusal (it
             ;; does not signal) — gate on that, or a declined prompt
             ;; would fall through and evaluate anyway.  That nil covers
             ;; BOTH an interactive "no" and a block whose `:eval'
             ;; policy never reached a prompt, so the check function
             ;; splits them: non-nil there means the user answered.
             (unless (org-babel-confirm-evaluate info)
               (if (org-babel-check-confirm-evaluate info)
                   (user-error "Evaluation declined")
                 (signal 'glasspane-table--disabled nil)))
             (let ((org-confirm-babel-evaluate nil))
               (with-timeout ((max 1 glasspane-babel-timeout)
                              (signal 'glasspane-table--timeout nil))
                 (org-babel-execute-src-block nil info)))))
          (glasspane-org-save-and-invalidate))
        (jetpacs-shell-notify "Block executed" surface)
        (ignore-errors (jetpacs-shell-push surface)))
    (inhibited-interaction
     (jetpacs-shell-notify glasspane-table--babel-refusal surface))
    (glasspane-table--timeout
     (jetpacs-shell-notify (format "Run timed out after %ss"
                                   (max 1 glasspane-babel-timeout))
                           surface))
    (glasspane-table--disabled
     (jetpacs-shell-notify "Evaluation disabled for this block" surface))
    (user-error
     (jetpacs-shell-notify "Evaluation declined" surface))
    (error
     (message "glasspane: babel run failed: %s" (jetpacs-error-label err))
     (jetpacs-shell-notify "Run failed" surface))))

;;;; Handlers (S4 — every one answers accepted/stale/rejected)

(defun glasspane-table--on-edit (args params)
  "Tap a table cell: gate, then hand the bridged editor its flow.
The grant check is the dispatch-time half of the bridge gate —
`jetpacs-dialog-can-bridge-p' itself is unanswerable inside a handler
(the in-action test wins), so the session halves reject here and the
flow re-checks where the prompt is actually raised."
  (let ((cell (glasspane-table--cell-gate args params "org.table.edit")))
    (cond
     ((symbolp cell) cell)
     ((not (and (jetpacs-connected-p)
                (jetpacs-granted-p "surfaces.dialog")))
      'rejected)
     (t
      (let ((surface (glasspane-table--flow-surface params)))
        (jetpacs-flow-begin surface
                            (lambda ()
                              (glasspane-table--edit-run
                               (car cell) (cdr cell) surface))))
      'accepted))))

(defun glasspane-table--on-cell-menu (args params)
  "Long-press a table cell: the bridged row/column structure menu."
  (let ((cell (glasspane-table--cell-gate args params "org.table.cell-menu")))
    (cond
     ((symbolp cell) cell)
     ((not (and (jetpacs-connected-p)
                (jetpacs-granted-p "surfaces.dialog")))
      'rejected)
     (t
      (let ((surface (glasspane-table--flow-surface params)))
        (jetpacs-flow-begin surface
                            (lambda ()
                              (glasspane-table--cell-menu-run
                               (car cell) (cdr cell) surface))))
      'accepted))))

(defun glasspane-table--on-add-row (args params)
  "The \"+\" strip under the table: append an empty row at the bottom,
then tap-to-edit fills it in.  No prompt — the mutation and save run
inside the dispatch (durable before `accepted'), only the repush
defers (D2)."
  (let ((cell (glasspane-table--cell-gate args params "org.table.add-row")))
    (if (symbolp cell)
        cell
      (condition-case err
          (progn
            (glasspane-table--mutate (car cell) (cdr cell)
                                     (lambda ()
                                       (goto-char (org-table-end))
                                       (forward-line -1) ; last table line
                                       (org-table-insert-row t)))
            (jetpacs-app-defer-refresh params)
            'accepted)
        (error
         (message "glasspane: add row failed: %s" (jetpacs-error-label err))
         (jetpacs-shell-notify "Add row failed" (plist-get params :surface))
         'rejected)))))

(defun glasspane-table--on-add-col (args params)
  "The \"+\" gutter at the right edge: append an empty column."
  (let ((cell (glasspane-table--cell-gate args params "org.table.add-col")))
    (if (symbolp cell)
        cell
      (condition-case err
          (progn
            (glasspane-table--mutate
             (car cell) (cdr cell)
             (lambda ()
               ;; Force-create a field one past the last column on the
               ;; first data line (pipe count is authoritative — \vert
               ;; never appears raw); the funnel's realign squares every
               ;; other row off to match.  `org-table-insert-column'
               ;; inserts to the LEFT of point's column, so it can't
               ;; append at the right edge directly.
               (goto-char (org-table-begin))
               (while (and (org-at-table-hline-p)
                           (< (point) (org-table-end)))
                 (forward-line 1))
               (let ((ncols (1- (cl-count ?| (buffer-substring-no-properties
                                              (line-beginning-position)
                                              (line-end-position))))))
                 (org-table-goto-column (1+ (max 1 ncols)) nil 'force))))
            (jetpacs-app-defer-refresh params)
            'accepted)
        (error
         (message "glasspane: add column failed: %s"
                  (jetpacs-error-label err))
         (jetpacs-shell-notify "Add column failed"
                               (plist-get params :surface))
         'rejected)))))

(defun glasspane-table--on-babel (args params)
  "The play button on a src-block header.  The wire names only a
location — the code that runs lives in the user's own file, so the
semantic-action boundary holds.  Execution ALWAYS defers: babel runs
for up to `glasspane-babel-timeout' seconds, which D2 keeps out of the
dispatch extent even when no confirm prompt is due.  The grant reject
here covers only what dispatch can know — the global confirm option
with no dialog grant; a per-block `:eval query' surfaces as the flow's
own refusal."
  (let ((cell (glasspane-table--cell-gate args params "org.babel.execute")))
    (cond
     ((symbolp cell) cell)
     ((and org-confirm-babel-evaluate
           (not (and (jetpacs-connected-p)
                     (jetpacs-granted-p "surfaces.dialog"))))
      (jetpacs-shell-notify glasspane-table--babel-refusal
                            (plist-get params :surface))
      'rejected)
     (t
      (let ((surface (glasspane-table--flow-surface params)))
        (jetpacs-flow-begin surface
                            (lambda ()
                              (glasspane-table--babel-run
                               (car cell) (cdr cell) surface))))
      'accepted))))

;;;; The app-authored table node (FOUNDATION-GAPS #11)

(defun glasspane-table--line-cells ()
  "The (TEXT . POS) cells of the table line at point.
POS is a buffer position INSIDE the field — the char after its opening
pipe, where the edit handlers put point.  Only complete |-delimited
fields count; `org-table-align' keeps rendered tables in that shape."
  (let* ((bol (line-beginning-position))
         (line (buffer-substring-no-properties bol (line-end-position)))
         (pipes nil)
         (i 0))
    (while (setq i (string-search "|" line i))
      (push (+ bol i) pipes)
      (setq i (1+ i)))
    (setq pipes (nreverse pipes))
    (let ((cells nil))
      (while (cdr pipes)
        (let ((a (car pipes)) (b (cadr pipes)))
          (push (cons (string-trim
                       (buffer-substring-no-properties (1+ a) b))
                      (1+ a))
                cells))
        (setq pipes (cdr pipes)))
      (nreverse cells))))

(defun glasspane-table--cell-node (cell buffer header)
  "One tappable table cell for (TEXT . POS) CELL in BUFFER.
Records the SPEC 23.1 exposures its two descriptors need — the edit
and cell-menu handlers refuse any position a render did not emit."
  (let ((text (car cell))
        (pos (cdr cell)))
    (jetpacs-buffer-expose buffer pos "org.table.edit")
    (jetpacs-buffer-expose buffer pos "org.table.cell-menu")
    (jetpacs-table-cell
     (list (if header
               (jetpacs-span text :font-weight "bold")
             (jetpacs-span text)))
     :on-tap (jetpacs-action "org.table.edit"
                             :args (list :buffer buffer :pos pos))
     :on-long-tap (jetpacs-action "org.table.cell-menu"
                                  :args (list :buffer buffer :pos pos)))))

(defun glasspane-table-node (el)
  "Buffer-current org table element EL as an editable native table node.
nil for a table.el table — that dialect has no org mutation commands
behind it.  The base render's own upgrade is read-only (gap #11), so
screens that want tap-to-edit author their tables here.  Rows above
the first hline render as the header group (org's own convention).
Exposure supersession is the CALLER's: sweep the buffer's records
\(`jetpacs-buffer-forget-exposed') once per re-render, before the
first table builds — this builder only adds.  Alignment cosmetics
stay client-default; the #+TBLFM line sits outside :contents-end and
is reachable through the computed cells it feeds."
  (when (eq (org-element-property :type el) 'org)
    (let* ((beg (org-element-property :contents-begin el))
           (end (org-element-property :contents-end el))
           (buffer (buffer-name))
           (raw nil))
      (save-excursion
        (goto-char beg)
        (while (< (point) end)
          (cond
           ((org-at-table-hline-p) (push 'hline raw))
           ((org-at-table-p) (push (glasspane-table--line-cells) raw)))
          (forward-line 1)))
      (setq raw (nreverse raw))
      (when raw
        (let ((has-header (and (memq 'hline raw)
                               (not (eq (car raw) 'hline))))
              (seen-hline nil))
          (jetpacs-buffer-expose buffer beg "org.table.add-row")
          (jetpacs-buffer-expose buffer beg "org.table.add-col")
          (jetpacs-table
           (mapcar
            (lambda (row)
              (if (eq row 'hline)
                  (progn (setq seen-hline t) (jetpacs-table-rule))
                (let ((header (and has-header (not seen-hline))))
                  (apply #'jetpacs-table-row (if header "header" "data")
                         (mapcar (lambda (cell)
                                   (glasspane-table--cell-node
                                    cell buffer header))
                                 row)))))
            raw)
           :on-add-row (jetpacs-action "org.table.add-row"
                                       :args (list :buffer buffer :pos beg))
           :on-add-col (jetpacs-action "org.table.add-col"
                                       :args (list :buffer buffer
                                                   :pos beg))))))))

;;;; Registration

(defconst glasspane-table--verbs
  '("org.table.edit"
    "org.table.cell-menu"
    "org.table.add-row"
    "org.table.add-col"
    "org.babel.execute")
  "The verbs this rung owns, for the register/unregister sweep.")

(defun glasspane-table-register ()
  "Register the table/babel verbs.
Called from `glasspane-register', not at this file's load (the G0
gate contract).  Idempotent: handlers replace in place."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "org.table.edit" #'glasspane-table--on-edit
                       :doc "Edit the tapped table cell (or its formula)")
    (jetpacs-defaction "org.table.cell-menu" #'glasspane-table--on-cell-menu
                       :doc "Row/column structure edits for a table cell")
    (jetpacs-defaction "org.table.add-row" #'glasspane-table--on-add-row)
    (jetpacs-defaction "org.table.add-col" #'glasspane-table--on-add-col)
    (jetpacs-defaction "org.babel.execute" #'glasspane-table--on-babel
                       :doc "Run the tapped source block")))

(defun glasspane-table-unregister ()
  "Drop the table/babel verbs."
  (dolist (name glasspane-table--verbs)
    (jetpacs-undefaction name)))

(provide 'glasspane-table)
;;; glasspane-table.el ends here
