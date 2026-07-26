;;; jetpacs-complete.el --- Emacs as the device editor's completion server -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JC-5 of docs/PLAN-jetpacs-consumers.md: REBUILD the direction, PORT
;; the harvester.
;;
;; poc-v1 pointed this module the other way: `edit.complete' arrived as
;; a custom ACTION carrying its own text window and `request_id', the
;; answer left as a `completions.show' frame, and jetpacs-sync owned the
;; document shadow and its staleness.  Under SPEC 19.3 `edit.complete'
;; is a REQUEST the Companion sends and ebp.el answers: ebp owns the
;; document MIRROR, refuses a stale query `1201 editor-stale' before any
;; application code runs, and consults the client-wide
;; `:edit-complete-function' hook — (DOCUMENT EDITOR-ID TEXT CURSOR) ->
;; (PREFIX . CANDIDATES).  So the action handler, the reply frame, the
;; request ids, and the whole jetpacs-sync coupling are DELETED, not
;; ported; what survives is the pure-Emacs harvester underneath them.
;;
;; The harvest: replay the mirror TEXT into a hidden shadow buffer
;; carrying the document's major mode, run the buffer's own
;; `completion-at-point-functions' there, and return the completed
;; prefix plus candidate plists.  Corfu/company/posframe never enter the
;; picture: they are UIs over capf, and the device brings its own UI
;; (the RenderEditor dropdown JC-4b built).  Emacs is the completion
;; SERVER.
;;
;; The shadow never visits a file (no disk access, no LSP session, no
;; mode hooks — `delay-mode-hooks'), so a completion request cannot
;; mutate anything: `edit.complete' stays the pure query SPEC 19.3
;; makes it.  Matching the document id against `auto-mode-alist' is not
;; the interpretation SPEC 4.4 forbids — this side MINTED the id when it
;; pushed the editor node, so the match reads our own naming convention,
;; and nothing is ever opened by that name.
;;
;; Candidate shape (SPEC 19.3): each candidate is a CLOSED object
;; {label, annotation?, insert?} with `insert' defaulting to `label'.
;; Closed is why the poc's `kind' member is dropped rather than carried:
;; a conformant Companion must REJECT an unknown member, so emitting it
;; would poison every reply that carried one.
;;
;; During a JC-4b picker prompt, `jetpacs-dialog' borrows the client's
;; `:edit-complete-function' slot and restores it at conclusion — this
;; harvester is the resting default underneath (`jetpacs-connect'
;; installs it when the caller supplied nothing), answering for real
;; synchronized editors; the dialog answers for its own picker document.

;;; Code:

(require 'cl-lib)

(defgroup jetpacs-complete nil
  "Emacs completion served to Companion editors."
  :group 'jetpacs)

(defcustom jetpacs-complete-enabled t
  "When non-nil, `jetpacs-complete-edit-complete' harvests candidates.
Set to nil to answer every completion request with an empty candidate
list (the device clears its dropdown); the round trips themselves stop
only when editor nodes are pushed without their `:complete' flag."
  :type 'boolean)

(defcustom jetpacs-complete-max-candidates 30
  "Maximum number of candidates returned per completion request.
The device dropdown shows a handful; anything past this cap is wasted
bytes on the wire."
  :type 'natnum)

(defcustom jetpacs-complete-debug nil
  "When non-nil, echo each completion request to *Messages*.
Logs the document, the resolved prefix, and the candidate count — a
live trace of the bridge working without a device on logcat.  The
prefix is user content, which is why this is opt-in and nil by default
(SPEC 23.3); the non-debug failure path logs error SYMBOLS only."
  :type 'boolean)

;;;; Shadow buffers

(defvar jetpacs-complete-shadow-setup-hook nil
  "Normal hook run in a shadow buffer once, at its creation.
The place to add buffer-local `completion-at-point-functions' or other
completion sources for device documents.  The buffer's (hook-delayed)
major mode is already set when it runs.")

(defun jetpacs-complete--mode-for (document)
  "The major mode DOCUMENT would get from `auto-mode-alist', or
`fundamental-mode'.  Never visits anything — the mode is chosen from
the id alone.  Honors `major-mode-remap', so a config that remaps to
tree-sitter modes gets them in the hidden shadows too."
  (let ((mode (assoc-default document auto-mode-alist #'string-match)))
    (when (and (symbolp mode) mode)
      (setq mode (major-mode-remap mode)))
    (if (and (symbolp mode) mode (fboundp mode)) mode 'fundamental-mode)))

(defun jetpacs-complete--shadow-buffer (document)
  "Get or create the hidden shadow buffer for DOCUMENT.
The buffer carries DOCUMENT's major mode so the right capfs are live,
but mode hooks are delayed: no LSP client, flycheck, or other machinery
spins up over a throwaway completion buffer.  The leading space in the
name keeps it out of buffer lists and disables undo."
  (let ((name (format " *jetpacs-complete: %s*" document)))
    (or (get-buffer name)
        (with-current-buffer (get-buffer-create name)
          (condition-case nil
              (delay-mode-hooks (funcall (jetpacs-complete--mode-for document)))
            (error (delay-mode-hooks (fundamental-mode))))
          (run-hooks 'jetpacs-complete-shadow-setup-hook)
          (current-buffer)))))

;;;; Candidate harvesting

(defun jetpacs-complete--capf-data ()
  "Run the buffer's capfs at point; return (BEG END TABLE . PROPS) or nil.
A capf that signals — e.g. text-mode's `ispell-completion-at-point'
with no dictionary installed — counts as producing nothing, so the
generic word fallback still gets its turn."
  (let ((res (condition-case nil
                 (run-hook-wrapped 'completion-at-point-functions
                                   #'completion--capf-wrapper 'all)
               (error nil))))
    (when (and (consp res) (consp (cdr res)) (numberp (cadr res)))
      (cdr res))))

(defun jetpacs-complete--word-fallback ()
  "Dabbrev-style fallback: words in the buffer sharing the token at point.
Returns (PREFIX . CANDIDATES) or nil.  Used when no capf produces
anything — plain text, org prose, unknown modes — so the dropdown is
never uselessly empty in a buffer full of repeated identifiers."
  (let* ((end (point))
         (beg (save-excursion (skip-syntax-backward "w_") (point))))
    (when (< beg end)
      (let ((prefix (buffer-substring-no-properties beg end))
            (case-fold-search nil)
            cands)
        (save-excursion
          (goto-char (point-min))
          (while (re-search-forward
                  (concat "\\_<" (regexp-quote prefix) "\\(?:\\sw\\|\\s_\\)+")
                  nil t)
            ;; Skip the token being completed itself.
            (unless (= (match-beginning 0) beg)
              (cl-pushnew (match-string-no-properties 0) cands :test #'equal))))
        (when cands (cons prefix (nreverse cands)))))))

(defun jetpacs-complete--annotate (fn cand)
  "Apply annotation function FN to CAND, trimmed; nil when absent or failing."
  (when fn
    (let ((a (condition-case nil (funcall fn cand) (error nil))))
      (when (and (stringp a) (not (string-empty-p (string-trim a))))
        (string-trim a)))))

(defun jetpacs-complete--collect ()
  "Harvest completions at point in the current buffer.
Returns (PREFIX . CANDIDATES) or nil.  Each candidate is a plist
\(:label L) plus optional :annotation and :insert — the SPEC 19.3
candidate object, ready for `ebp-client--handle-edit-complete' to
vector-wrap and serialize.  Candidates are sorted shortest-first (the
likeliest next keystroke saver), capped at
`jetpacs-complete-max-candidates'."
  (let* ((data (jetpacs-complete--capf-data))
         (beg (nth 0 data))
         (table (nth 2 data))
         (props (nthcdr 3 data))
         (ann-fn (plist-get props :annotation-function))
         ;; Capf extension: what a candidate INSERTS when it differs
         ;; from its display label — a wikilink chip shows "[[Title" but
         ;; lands "[[id:…][Title]]" in the buffer.  Feeds SPEC 19.3's
         ;; `insert' member, which defaults to `label' when omitted.
         (insert-fn (plist-get props :jetpacs-insert-function))
         ;; The device replaces text *before* the cursor, so the prefix
         ;; is [BEG, point) even when the capf's END extends past point
         ;; (SPEC 19.3: the prefix is the substring immediately before
         ;; the requested cursor that the candidate will replace).
         (prefix (and data (buffer-substring-no-properties beg (point))))
         ;; Lazy tables can signal when queried (ispell again), hence the
         ;; condition-case: a broken table degrades to the fallback.
         (cands (and prefix
                     (condition-case nil
                         (all-completions prefix table
                                          (plist-get props :predicate))
                       (error nil))))
         ;; An empty prefix is legitimate LSP member completion (right
         ;; after "." the server returns a small, precise list) but on an
         ;; unconstrained table (elisp's obarray) it means *everything* —
         ;; keep the former, drop the latter by sheer size.
         (cands (if (and cands (string-empty-p prefix)
                         (> (length cands) 500))
                    nil
                  cands)))
    ;; Empty capf result -> generic word fallback (org prose, unknown modes).
    (unless cands
      (when-let* ((fb (jetpacs-complete--word-fallback)))
        (setq prefix (car fb) cands (cdr fb)
              ann-fn nil insert-fn nil)))
    (when cands
      (setq cands (sort (delete-dups
                         (mapcar #'substring-no-properties cands))
                        (lambda (a b) (or (< (length a) (length b))
                                          (and (= (length a) (length b))
                                               (string< a b))))))
      ;; Sole candidate == what's already typed: nothing to offer.
      (setq cands (delete prefix cands))
      (when cands
        (cons prefix
              (mapcar (lambda (c)
                        (let ((node (list :label c)))
                          (when-let* ((a (jetpacs-complete--annotate ann-fn c)))
                            (setq node (append node (list :annotation a))))
                          (let ((ins (and insert-fn
                                          (condition-case nil
                                              (funcall insert-fn c)
                                            (error nil)))))
                            (when (and (stringp ins) (not (equal ins c)))
                              (setq node (append node (list :insert ins)))))
                          node))
                      (seq-take cands jetpacs-complete-max-candidates)))))))

(defun jetpacs-complete-in-text (document text cursor)
  "Complete DOCUMENT's TEXT at CURSOR (0-based Unicode scalar offset).
Replays TEXT into DOCUMENT's shadow buffer and harvests candidates
there.  Emacs characters ARE scalar values, so CURSOR maps to a buffer
position directly.  Returns (PREFIX . CANDIDATES) or nil.  Separated
from the seam function so tests can call it directly."
  (with-current-buffer (jetpacs-complete--shadow-buffer document)
    (erase-buffer)
    (insert text)
    (goto-char (min (1+ (max 0 (truncate cursor))) (point-max)))
    (jetpacs-complete--collect)))

;;;; The ebp seam

(defun jetpacs-complete-edit-complete (document _editor-id text cursor)
  "Answer `edit.complete' for DOCUMENT from its shadow buffer.
The `ebp-client-create' `:edit-complete-function' contract: called with
\(DOCUMENT EDITOR-ID TEXT CURSOR) only after ebp.el matched the query's
session and seq against the live mirror (a stale query was already
refused `1201 editor-stale', SPEC 19.3), TEXT the full mirror text.
Returns (PREFIX . CANDIDATES) or nil; ebp turns nil into the empty
reply, which is how the device clears its dropdown.

A harvest error also degrades to the empty reply — a broken capf must
cost a missing dropdown, never a `-32603' on the wire.  Install as the
connect-time default via `jetpacs-connect', or directly:
  (ebp-connect HOST PORT :edit-complete-function
               #\\='jetpacs-complete-edit-complete …)"
  (when (and jetpacs-complete-enabled (stringp text) (numberp cursor))
    (let ((result (condition-case err
                      (jetpacs-complete-in-text document text cursor)
                    ;; The error SYMBOL only (SPEC 23.3):
                    ;; `error-message-string' embeds the datum, and the
                    ;; datum here is buffer content.
                    (error (message "jetpacs-complete: harvest failed (%s)"
                                    (car err))
                           nil))))
      (when jetpacs-complete-debug
        (if result
            (message "jetpacs-complete: %s prefix=%S -> %d candidate(s)"
                     document (car result) (length (cdr result)))
          (message "jetpacs-complete: %s -> nothing to offer at cursor"
                   document)))
      result)))

(provide 'jetpacs-complete)
;;; jetpacs-complete.el ends here
