;;; jetpacs-repl.el --- An Elisp REPL, as device chrome -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The read-eval-print loop the device hub has had since 2026-08-06,
;; lifted out of `device/init.el' so it can have a second caller.
;;
;; It was library work living in personal configuration: a *scratch*-style
;; multi-form evaluator feeding `*' `**' `***', a history of results with
;; copy and re-run, and a pinned input row that is a SYNCHRONIZED §19
;; editor rather than a local draft.  None of that is about being a home
;; screen.  The M3 catalog's Playground wants exactly the same loop over a
;; different subject, and the choice was to duplicate it or to name it.
;;
;; SESSIONS.  Everything here is keyed by a session id, so two REPLs on
;; one device keep separate histories and separate editor documents while
;; sharing one evaluator — and therefore one `*' `**' `***' chain, which
;; is correct: those are Emacs's, not a screen's, and a value yielded in
;; one REPL should be reachable from the other exactly as it would be
;; between two ielm buffers.
;;
;; THE DOCUMENT ID ENDS `.el' ON PURPOSE.  `ebp-complete--mode-for'
;; matches the document against `auto-mode-alist' to pick the shadow
;; buffer's major mode, and that is the whole mechanism by which the
;; phone gets REAL `elisp-completion-at-point' — Emacs is the completion
;; server (SPEC 19.3), the device brings the UI.  A document id without
;; the suffix silently answers nothing.
;;
;; ON EVALUATION AND SPEC 23.2.  §23.2 forbids executing text obtained
;; from an editor field "without a separate explicit trust decision", and
;; a REPL plainly evaluates text obtained from an editor field.  The
;; reading this module rests on: §23.2's subject is text arriving from a
;; QR code, a clipboard, a share intent or a notification into a facility
;; that was not asking for code — the case where the user intended to
;; SEND text, not to run it.  A REPL's input is a field the user
;; knowingly typed a form into for the purpose of evaluating it, and the
;; send tap is the per-invocation act.  There is no ambient promotion
;; here: nothing else on the surface reaches this evaluator, and the
;; editor is not fed by any platform channel.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'jetpacs-widgets)

(defcustom jetpacs-repl-history-max 50
  "Results kept per REPL session, newest first."
  :type 'integer :group 'jetpacs)

(defcustom jetpacs-repl-output-max 2000
  "Characters of one result shown before it is elided.
The whole value is still what Copy yields — this bounds the CARD, not
the record, because a result that prints a buffer's worth of text would
otherwise push every earlier result off the screen."
  :type 'integer :group 'jetpacs)

(defvar jetpacs-repl--history (make-hash-table :test #'equal)
  "Session id -> a list of (INPUT OUTPUT ERRORP), newest first.")

;; ielm's last-three-values, declared special because we assign them.
;; They are deliberately NOT `jetpacs-' prefixed and deliberately not
;; owned here: `*' `**' `***' are the names any Emacs user reaches for
;; after evaluating something, and a REPL that spelled them privately
;; would be a REPL you cannot chain in.  The value-less `defvar' form
;; marks them dynamic without claiming an initial value from ielm.
(defvar *)
(defvar **)
(defvar ***)

;;;; The loop

(defun jetpacs-repl-eval-forms (input)
  "Evaluate every form in INPUT like *scratch* would; return the last value.
Feeds `*' `**' `***' the way ielm does, so a follow-up expression can
chain off what the last one produced.

Reading the whole string and evaluating form by form — rather than
`read'ing once — is what makes a pasted region behave the way the same
region behaves under \\[eval-region]."
  (let ((last nil))
    (with-temp-buffer
      (insert input)
      (goto-char (point-min))
      (condition-case nil
          (while t (setq last (eval (read (current-buffer)) t)))
        (end-of-file nil)))
    (set '*** (and (boundp '**) (symbol-value '**)))
    (set '** (and (boundp '*) (symbol-value '*)))
    (set '* last)
    last))

(defun jetpacs-repl-history (session)
  "SESSION's results, newest first."
  (gethash session jetpacs-repl--history))

(defun jetpacs-repl-clear (session)
  "Forget SESSION's results."
  (remhash session jetpacs-repl--history))

(defun jetpacs-repl-record (session input output errorp)
  "Record OUTPUT for INPUT in SESSION, trimming to the history cap.
Separate from `jetpacs-repl-run' because recording and evaluating are
different powers: a caller that already has a result — a test fixture, a
sample that produced its value some other way — should be able to put it
in the history without going near `eval'."
  (puthash session
           (seq-take (cons (list input output errorp)
                           (gethash session jetpacs-repl--history))
                     jetpacs-repl-history-max)
           jetpacs-repl--history))

(defun jetpacs-repl-run (session input)
  "Evaluate INPUT for SESSION, record the result, and return it.
Returns (VALUE OUTPUT ERRORP): VALUE is the datum — a caller that wants
to RENDER a returned node needs the value, not its printed form — and
OUTPUT is what the card shows.

A signal is a result, not a failure: it is recorded and displayed in the
error color, because a REPL that loses your traceback is worse than one
that shows it.  `quit' is caught for the same reason \\[keyboard-quit]
during a long evaluation should leave the loop standing."
  (let (value output errorp)
    (condition-case err
        (setq value (jetpacs-repl-eval-forms input)
              output (prin1-to-string value))
      (error (setq output (error-message-string err) errorp t))
      (quit (setq output "Quit" errorp t)))
    (jetpacs-repl-record session input output errorp)
    (list value output errorp)))

;;;; The chrome

(cl-defun jetpacs-repl-card (entry &key index verb)
  "One history ENTRY as a card: the input, the result, copy and re-run.
VERB is the action name re-run dispatches, carrying the input as
`:value'; INDEX is only for the reconciliation key."
  (pcase-let* ((`(,input ,output ,errorp) entry)
               (shown (if (> (length output) jetpacs-repl-output-max)
                          (concat (substring output 0 jetpacs-repl-output-max)
                                  " …")
                        output)))
    (jetpacs-with-attrs
     (jetpacs-card
      (jetpacs-column
       (jetpacs-row
        (jetpacs-with-attrs
         (jetpacs-text (concat "λ> " input) :style "label" :max-lines 2)
         :weight 1)
        ;; A BUILTIN copy, so it still works while Emacs is busy in a
        ;; long evaluation — which is exactly when a result is worth
        ;; taking somewhere else.
        (jetpacs-icon-button "content_copy" (jetpacs-clipboard-copy output)
                             :content-description "Copy result")
        (jetpacs-icon-button "play_arrow"
                             (jetpacs-action verb :args (list :value input))
                             :content-description "Re-run"))
       (jetpacs-text shown :style "mono" :selectable t
                     :color (and errorp "error"))))
     :key (jetpacs-wire-id "replcard" (format "%d" (or index 0))))))

(cl-defun jetpacs-repl-cards (session &key verb)
  "SESSION's history as cards, newest first — a LIST of nodes."
  (cl-loop for entry in (jetpacs-repl-history session)
           for index from 0
           collect (jetpacs-repl-card entry :index index :verb verb)))

(cl-defun jetpacs-repl-input-row (&key editor-id document verb value)
  "The pinned input row: an elisp editor and the button that submits it.

DOCUMENT must end `.el' — see the Commentary; that suffix is what makes
Emacs answer `edit.complete' with real elisp candidates.  VERB is the
action both the editor's Enter and the send button dispatch.  VALUE
seeds the field.

The send button is FILLED.  Authored bare it is, per
`jetpacs-icon-button''s own docstring, \"the plain, container-less icon
button\" — and a container-less glyph beside a chromeless editor does
not read as the primary action of the screen.  It was one, and did not
look like one."
  (unless (string-suffix-p ".el" document)
    (error "jetpacs-repl: :document %S must end in `.el' so the elisp capfs answer"
           document))
  (jetpacs-with-attrs
   (jetpacs-row
    (jetpacs-with-attrs
     (apply #'jetpacs-editor editor-id
            :document document :complete t :chromeless t :syntax "elisp"
            :on-enter (jetpacs-action verb)
            (and value (list :value value)))
     :weight 1)
    (jetpacs-icon-button "send" (jetpacs-action verb)
                         :variant "filled"
                         :content-description "Eval"))
   :padding 8))

(defun jetpacs-repl-empty-state ()
  "The card list's resting state, before anything has been evaluated."
  (jetpacs-empty-state
   :icon "code" :title "Elisp REPL"
   :caption (concat "Results appear here, newest first.  "
                    "* ** and *** hold the last three results.")))

(provide 'jetpacs-repl)
;;; jetpacs-repl.el ends here
