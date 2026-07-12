;;; glasspane-table.el --- Glasspane UI component -*- lexical-binding: t; -*-
;;; Code:

(require 'glasspane-ui)

(jetpacs-defaction "org.footnote.show"
  ;; A tapped footnote marker in rich text: surface its inline definition
  ;; (when the reference carried one) or just its label.
  (lambda (args _)
    (let ((def (alist-get 'def args))
          (label (alist-get 'label args)))
      (jetpacs-shell-notify
       (if (and (stringp def) (not (string-empty-p def)))
           (format "Footnote: %s" def)
         (format "Footnote %s" (or label ""))))
      (jetpacs-shell-push))))

;; The org settings exposed to the companion, through the generic
;; schema-driven machinery (the registry is the security boundary:
;; only symbols listed here can be modified from the wire).  Registered
;; under the app's owner id, so coexisting apps' settings never
;; interleave: these sections render only while Glasspane is current.
(with-jetpacs-owner "glasspane"
  (jetpacs-settings-register-section
   "Org Workflow"
   '((org-directory :label "Org directory")
     (org-log-done :label "Log task completion")
     (org-log-into-drawer :label "Log into drawer")
     (org-archive-location :label "Archive location")))
  (jetpacs-settings-register-section
   "Org Agenda"
   '((org-agenda-span :label "Agenda span")
     (org-deadline-warning-days :label "Deadline warning days")
     (org-extend-today-until :label "Extend today until (hour)")))
  (jetpacs-settings-register-section
   "Org Editing & Display"
   '((org-startup-folded :label "Initial folding")
     (org-startup-indented :label "Indent to outline level")
     (org-hide-emphasis-markers :label "Hide emphasis markers")
     (org-return-follows-link :label "Enter follows links")
     (glasspane-babel-timeout :label "Babel run timeout (s)")))
  (jetpacs-settings-register-section
   "User Defaults"
   '((user-full-name :label "Author (Name)")
     (user-mail-address :label "Email")))
  (jetpacs-settings-register-section
   "Calendar & Location"
   '((calendar-week-start-day :label "Week start day (0=Sun, 1=Mon)")
     (calendar-latitude :label "Latitude (e.g. 40.7)")
     (calendar-longitude :label "Longitude (e.g. -74.0)")))
  (jetpacs-settings-register-section
   "Appearance"
   '((jetpacs-dialog-style :label "Dialog presentation"))))

;; ─── Table actions ───────────────────────────────────────────────────────────
;; The rich renderer emits native `table' nodes whose cells and "+"
;; affordances carry these actions with real-file positions baked in.

(defun glasspane-ui--table-mutate (file pos fn)
  "Run FN with point at POS inside FILE's table, then align, save, repush.
FN performs one table mutation.  Afterwards the table is realigned,
recalculated when a #+TBLFM line follows it (formulas live Emacs-side —
the phone never computes), saved, and every view repushed.  A mutation
that moves point off the table (killing a row) realigns from the
table's start; one that consumes the table entirely (killing its only
row) skips the realign instead of erroring."
  (with-current-buffer (find-file-noselect file)
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
    (let ((glasspane-org--inhibit-save-refresh t)
          (save-silently t))
      (save-buffer)))
  (glasspane-org-cache-invalidate)
  (jetpacs-shell-push))

(defun glasspane-ui--table-field-formula ()
  "The #+TBLFM entry (LHS . RHS) computing the field at point, or nil.
Field formulas (@R$C, with @< / @> resolved to concrete rows) win over
column formulas ($C), mirroring org's own recalculation.  Point must be
inside a table.  The LHS comes back exactly as written in the #+TBLFM
line, so callers can `assoc' it in `org-table-get-stored-formulas'
output to update the formula in place.  Formulas keyed by field name
are not resolved — those cells stay value-editable."
  (org-table-analyze)
  (let* ((line (count-lines org-table-current-begin-pos
                            (line-beginning-position)))
         (dline (org-table-line-to-dline line))
         (col (org-table-current-column))
         (stored (org-table-get-stored-formulas t))
         (norm (lambda (kv)
                 (or (ignore-errors
                       (org-table-formula-handle-first/last-rc (car kv)))
                     (car kv)))))
    (when (and dline col (> col 0))
      (or (cl-find (format "@%d$%d" dline col) stored :key norm :test #'equal)
          (cl-find (format "$%d" col) stored :key norm :test #'equal)))))

(jetpacs-defaction "org.table.edit"
  ;; Tap a table cell in the reader: a native dialog (bridged
  ;; `read-string') prefilled with the current field, written back
  ;; through the org table machinery so formulas recalculate.  A field
  ;; that #+TBLFM computes opens its formula instead — recalculation
  ;; would immediately overwrite any value typed into it.
  (lambda (args _)
    (let ((file (alist-get 'file args))
          (pos  (alist-get 'pos args)))
      (when (and file pos (file-readable-p file))
        (condition-case err
            (let (current formula)
              (with-current-buffer (find-file-noselect file)
                (org-with-wide-buffer
                 (goto-char pos)
                 (unless (org-at-table-p) (error "No table cell here"))
                 (setq formula (glasspane-ui--table-field-formula))
                 (unless formula
                   (setq current (string-trim (org-table-get-field))))))
              (if formula
                  (let ((input (string-trim
                                (read-string (format "Formula %s= " (car formula))
                                             (cdr formula)))))
                    (when (string-empty-p input)
                      (error "Empty formula — edit the #+TBLFM line to remove one"))
                    (glasspane-ui--table-mutate file pos
                      (lambda ()
                        (let* ((stored (org-table-get-stored-formulas t))
                               (entry (or (assoc (car formula) stored)
                                          (error "Formula %s not found"
                                                 (car formula)))))
                          (setcdr entry input)
                          (save-excursion
                            (org-table-store-formulas stored))))))
                (let* ((input (read-string "Cell: " current))
                       ;; A field is one line between pipes — keep it that way.
                       (new (string-replace
                             "|" "\\vert{}"
                             (string-replace "\n" " " input))))
                  (glasspane-ui--table-mutate file pos
                    (lambda () (org-table-get-field nil new))))))
          (error
           (jetpacs-shell-notify
            (format "Edit failed: %s" (error-message-string err)))
           (jetpacs-shell-push)))))))

(jetpacs-defaction "org.table.cell-menu"
  ;; Long-press a table cell in the reader: row/column structure edits
  ;; picked from a bridged `completing-read'.  Org's own commands fix up
  ;; #+TBLFM references (or mark them INVALID) on the way through.
  (lambda (args _)
    (let ((file (alist-get 'file args))
          (pos  (alist-get 'pos args)))
      (when (and file pos (file-readable-p file))
        (condition-case err
            (let ((choice (completing-read
                           "Row/column: "
                           '("Insert row above" "Insert column left"
                             "Delete row" "Delete column")
                           nil t)))
              (glasspane-ui--table-mutate file pos
                (lambda ()
                  (pcase choice
                    ("Insert row above"   (org-table-insert-row))
                    ("Insert column left" (org-table-insert-column))
                    ("Delete row"         (org-table-kill-row))
                    ("Delete column"      (org-table-delete-column))))))
          (error
           (jetpacs-shell-notify
            (format "Table edit failed: %s" (error-message-string err)))
           (jetpacs-shell-push)))))))

(jetpacs-defaction "org.table.add-row"
  ;; The "+" strip under the table: append an empty row at the bottom,
  ;; then tap-to-edit fills it in.
  (lambda (args _)
    (let ((file (alist-get 'file args))
          (pos  (alist-get 'pos args)))
      (when (and file pos (file-readable-p file))
        (condition-case err
            (glasspane-ui--table-mutate file pos
              (lambda ()
                (goto-char (org-table-end))
                (forward-line -1)       ; last table line
                (org-table-insert-row t)))
          (error
           (jetpacs-shell-notify
            (format "Add row failed: %s" (error-message-string err)))
           (jetpacs-shell-push)))))))

(jetpacs-defaction "org.table.add-col"
  ;; The "+" gutter at the right edge: append an empty column.
  (lambda (args _)
    (let ((file (alist-get 'file args))
          (pos  (alist-get 'pos args)))
      (when (and file pos (file-readable-p file))
        (condition-case err
            (glasspane-ui--table-mutate file pos
              (lambda ()
                ;; Force-create a field one past the last column on the
                ;; first data line (pipe count is authoritative — \vert
                ;; never appears raw); the helper's realign squares every
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
          (error
           (jetpacs-shell-notify
            (format "Add column failed: %s" (error-message-string err)))
           (jetpacs-shell-push)))))))

(jetpacs-defaction "org.babel.execute"
  ;; The play button on a src-block header.  The wire names only a
  ;; location — the code that runs lives in the user's own file, so the
  ;; semantic-action boundary holds.  `org-confirm-babel-evaluate' is
  ;; honored: the yes/no prompt bridges to a native dialog, and it runs
  ;; BEFORE the timeout starts so a slow answer never counts against the
  ;; execution budget.
  (lambda (args _)
    (let ((file (alist-get 'file args))
          (pos  (alist-get 'pos args)))
      (when (and file pos (file-readable-p file))
        (condition-case err
            (progn
              (with-current-buffer (find-file-noselect file)
                (org-with-wide-buffer
                 (goto-char pos)
                 (let ((info (org-babel-get-src-block-info)))
                   (unless info (error "No source block here"))
                   ;; `org-babel-confirm-evaluate' RETURNS nil on decline (it
                   ;; does not signal) — gate on that, or a declined prompt
                   ;; would fall through and evaluate anyway.
                   (unless (org-babel-confirm-evaluate info)
                     (user-error "Evaluation declined"))
                   (let ((org-confirm-babel-evaluate nil))
                     (with-timeout ((max 1 glasspane-babel-timeout)
                                    (error "Timed out after %ss"
                                           glasspane-babel-timeout))
                       (org-babel-execute-src-block nil info)))))
                (let ((glasspane-org--inhibit-save-refresh t)
                      (save-silently t))
                  (save-buffer)))
              (glasspane-org-cache-invalidate)
              (jetpacs-shell-notify "Block executed")
              (jetpacs-shell-push))
          (error
           (jetpacs-shell-notify
            (format "Run failed: %s" (error-message-string err)))
           (jetpacs-shell-push)))))))

(provide 'glasspane-table)
