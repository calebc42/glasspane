;;; glasspane-journal.el --- Deprecated journal capture alias -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; PA-4 retired the legacy Journal screen, its navigation verbs, and the
;; session-landing hook.  This module retains only the headless
;; `journal.capture' datetree-append alias (`docs/PLAN-glasspane-para.md'
;; §0.11, §3) so queued offline receipts (`:ttl-s 86400') replay cleanly to
;; disk before the alias itself is retired in a later release.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-datetree)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-apps)
(require 'glasspane-org)

(defcustom glasspane-journal-file nil
  "The journal file holding the datetree.
nil means journal.org inside `org-directory'."
  :type '(choice (const :tag "journal.org in org-directory" nil) file)
  :group 'jetpacs)

(defun glasspane-journal--file ()
  "Return the journal file path."
  (or glasspane-journal-file
      (expand-file-name "journal.org" org-directory)))

(defun glasspane-journal--today ()
  "Return today's ISO date string."
  (format-time-string "%Y-%m-%d"))

;;;; The datetree seam

(defun glasspane-journal--append (text &optional date)
  "Append TEXT as a plain list item under DATE's (default today) day.
Creates the datetree levels (and the file) on first use.  Saves NOW
through `glasspane-org-save-and-invalidate' — the capture handler's
`accepted' promises on-disk, never on-timer (S4)."
  (let ((date (or date (glasspane-journal--today)))
        (file (glasspane-journal--file)))
    (pcase-let ((`(,y ,m ,d) (mapcar #'string-to-number
                                     (split-string date "-"))))
      (ebp-org--with-clamped-io
        (with-current-buffer (find-file-noselect file t)
          (org-with-wide-buffer
           (org-datetree-find-date-create (list m d y))
           (org-back-to-heading t)
           (org-end-of-subtree t t)
           (unless (bolp) (insert "\n"))
           (insert "- " text "\n"))
          (glasspane-org-save-and-invalidate))))))

;;;; Handlers (S4 — answers accepted/rejected)

(defun glasspane-journal--on-capture (args params)
  "Append the submitted text in ARGS to `:date' (default today).
PARAMS carries the originating action event.  Returns `accepted' only after
the append is saved (S4 durable — this is also what makes the queued replay
honest); a failed append logs and toasts the SPEC 23.3 label, never the raw
error."
  (let ((raw (plist-get args :value))
        (date (plist-get args :date)))
    (if (or (not (stringp raw)) (string-empty-p (string-trim raw)))
        'rejected
      ;; SPEC 23.2 — neutralize wire text before it becomes org
      ;; structure.  The append lands at end-of-subtree, so an embedded
      ;; newline would promote the payload out of the list item into a
      ;; heading, a keyword line or a local-variables block.  Collapsed
      ;; HERE and not in `glasspane-journal--append': that path is
      ;; M-x/internal, its text is not wire input.
      (let ((text (string-trim
                   (replace-regexp-in-string "[ \t\n\r]+" " " raw))))
        (condition-case err
            (progn
              (glasspane-journal--append
               text
               (and (stringp date) (not (string-empty-p date)) date))
              (jetpacs-shell-notify "Added to journal")
              (jetpacs-app-defer-refresh params)
              'accepted)
          (error
           (message "glasspane: journal capture failed: %s"
                    (jetpacs-error-label err))
           (jetpacs-toast "Capture failed")
           'rejected))))))

;;;; Registration

(defconst glasspane-journal--verbs
  '("journal.capture")
  "The verbs this module owns, for the register/unregister sweep.")

(defun glasspane-journal-register ()
  "Register the deprecated headless `journal.capture' alias idempotently.
Called from `glasspane-register', never at this file's load (the G0
gate contract)."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "journal.capture" #'glasspane-journal--on-capture
                       :doc "Deprecated headless journal datetree append alias."
                       :args '((:name value :type "text" :required t)
                               (:name date :type "date")))))

(defun glasspane-journal-unregister ()
  "Drop the journal capture alias."
  (dolist (name glasspane-journal--verbs)
    (jetpacs-undefaction name)))

(provide 'glasspane-journal)
;;; glasspane-journal.el ends here
