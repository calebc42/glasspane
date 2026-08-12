;;; ebp-complete.el --- Emacs as the completion server for EBP editors -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; `ebp-' by the ratified rule (2026-08-06): `jetpacs-' is for what
;; cannot exist without Kotlin, Android, and Compose; `ebp-' is for what
;; only ever touches the wire and Emacs.  This file is the second kind
;; and always was — it requires `cl-lib' and nothing else, and its whole
;; contract is a SPEC 19.3 shape (`edit.complete' in, {label,
;; annotation?, insert?} out) harvested from Emacs's own capf machinery.
;; Not one node, builder, or surface appears below.  The prefix said
;; otherwise for a while; now it does not, and the delineation guard can
;; hold it to that.
;;
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
;; R0 of the completion ladder (docs/PLAN-glasspane-completion.md): the
;; shadow is not the only arm any more.  When `ebp-sync' holds a live
;; attached buffer for the document — the jetpacs-files editor screen
;; and the hub REPL attach exactly this way — the harvest runs THERE,
;; because the live buffer carries completion sources the shadow can
;; never have: an eglot-managed buffer's LSP capf above all, plus every
;; buffer-local addition.  The shadow remains the answer for documents
;; nothing attached (dialog seeds, never-visited ids) and the fallback
;; when the live arm cannot answer (text diverged mid-flush, a slow
;; backend overran `ebp-complete-live-timeout').
;;
;; Who installs the harvester is the layer above's business: this
;; module names no caller and requires none.  For the reader — Jetpacs
;; makes it the connect-time default (`jetpacs-connect', when the caller
;; supplied nothing), and a JC-4b picker prompt registers its own source
;; for its own document in ebp.el's `edit-complete-overrides' table, so
;; the harvester keeps answering for every other document while a
;; prompt is up.

;;; Code:

(require 'cl-lib)

;; A seam, never a require: the live-buffer arm exists only when
;; `ebp-sync' is loaded, and this module's whole dependency surface
;; stays `cl-lib' (the delineation the commentary promises).
(declare-function ebp-sync-attached-buffer "ebp-sync" (document editor-id))

(defgroup ebp-complete nil
  "Emacs completion served to Companion editors."
  :group 'ebp)

(defcustom ebp-complete-enabled t
  "When non-nil, `ebp-complete-edit-complete' harvests candidates.
Set to nil to answer every completion request with an empty candidate
list (the device clears its dropdown); the round trips themselves stop
only when editor nodes are pushed without their `:complete' flag."
  :type 'boolean)

(defcustom ebp-complete-max-candidates 30
  "Maximum number of candidates returned per completion request.
The device dropdown shows a handful; anything past this cap is wasted
bytes on the wire."
  :type 'natnum)

(defcustom ebp-complete-live-timeout 1.0
  "Seconds the live-buffer arm may spend before the shadow answers.
A live buffer's capfs can block — eglot's waits on a language server —
and `edit.complete' is answered inside a jsonrpc request handler, so a
thinking server must cost a degraded answer, never a stuck session.
The bound is best-effort (`with-timeout'): a backend waiting on process
output is interrupted; one spinning in C without yielding is not."
  :type 'number)

(defcustom ebp-complete-debug nil
  "When non-nil, echo each completion request to *Messages*.
Logs the document, the resolved prefix, and the candidate count — a
live trace of the bridge working without a device on logcat.  The
prefix is user content, which is why this is opt-in and nil by default
(SPEC 23.3); the non-debug failure path logs error SYMBOLS only."
  :type 'boolean)

;;;; Shadow buffers

(defvar ebp-complete-shadow-setup-hook nil
  "Normal hook run in a shadow buffer once, at its creation.
The place to add buffer-local `completion-at-point-functions' or other
completion sources for device documents.  The buffer's (hook-delayed)
major mode is already set when it runs.")

(defun ebp-complete--mode-for (document)
  "The major mode DOCUMENT would get from `auto-mode-alist', or
`fundamental-mode'.  Never visits anything — the mode is chosen from
the id alone.  Honors `major-mode-remap', so a config that remaps to
tree-sitter modes gets them in the hidden shadows too."
  (let ((mode (assoc-default document auto-mode-alist #'string-match)))
    (when (and (symbolp mode) mode)
      (setq mode (major-mode-remap mode)))
    (if (and (symbolp mode) mode (fboundp mode)) mode 'fundamental-mode)))

(defun ebp-complete--shadow-buffer (document)
  "Get or create the hidden shadow buffer for DOCUMENT.
The buffer carries DOCUMENT's major mode so the right capfs are live,
but mode hooks are delayed: no LSP client, flycheck, or other machinery
spins up over a throwaway completion buffer.  The leading space in the
name keeps it out of buffer lists and disables undo."
  (let ((name (format " *ebp-complete: %s*" document)))
    (or (get-buffer name)
        (with-current-buffer (get-buffer-create name)
          (condition-case nil
              (delay-mode-hooks (funcall (ebp-complete--mode-for document)))
            (error (delay-mode-hooks (fundamental-mode))))
          (run-hooks 'ebp-complete-shadow-setup-hook)
          (current-buffer)))))

;;;; Candidate harvesting

(defun ebp-complete--capf-data ()
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

(defun ebp-complete--word-fallback ()
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

(defun ebp-complete--annotate (fn cand)
  "Apply annotation function FN to CAND, trimmed; nil when absent or failing."
  (when fn
    (let ((a (condition-case nil (funcall fn cand) (error nil))))
      (when (and (stringp a) (not (string-empty-p (string-trim a))))
        (string-trim a)))))

(defvar ebp-complete--collect-extras nil
  "Post-wire leftovers of the most recent `ebp-complete--collect'.
A plist (:exit-fn FN :raw CANDIDATES) — the capf's `:exit-function'
and the candidate strings BEFORE `substring-no-properties', whose text
properties carry what an exit function reads (eglot's LSP item above
all).  Set on every collect that ran a capf, nil otherwise; consumed
by `ebp-complete--live-harvest' to mint the accept offer (R2).  The
wire never sees any of it.")

(defun ebp-complete--collect ()
  "Harvest completions at point in the current buffer.
Returns (PREFIX . CANDIDATES) or nil.  Each candidate is a plist
\(:label L) plus optional :annotation and :insert — the SPEC 19.3
candidate object, ready for `ebp-client--handle-edit-complete' to
vector-wrap and serialize.  Candidates are sorted shortest-first (the
likeliest next keystroke saver), capped at
`ebp-complete-max-candidates'."
  (let* ((data (ebp-complete--capf-data))
         (beg (nth 0 data))
         (table (nth 2 data))
         (props (nthcdr 3 data))
         (ann-fn (plist-get props :annotation-function))
         ;; Capf extension: what a candidate INSERTS when it differs
         ;; from its display label — a wikilink chip shows "[[Title" but
         ;; lands "[[id:…][Title]]" in the buffer.  Feeds SPEC 19.3's
         ;; `insert' member, which defaults to `label' when omitted.
         (insert-fn (plist-get props :ebp-insert-function))
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
    ;; The accept-offer leftovers (R2): recorded only for a REAL capf
    ;; harvest — the word fallback has no exit function and its strings
    ;; carry nothing — and BEFORE the wire strip below removes the text
    ;; properties an exit function reads.
    (setq ebp-complete--collect-extras
          (and cands
               (list :exit-fn (plist-get props :exit-function)
                     :raw cands)))
    ;; Empty capf result -> generic word fallback (org prose, unknown modes).
    (unless cands
      (when-let* ((fb (ebp-complete--word-fallback)))
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
                          (when-let* ((a (ebp-complete--annotate ann-fn c)))
                            (setq node (append node (list :annotation a))))
                          (let ((ins (and insert-fn
                                          (condition-case nil
                                              (funcall insert-fn c)
                                            (error nil)))))
                            (when (and (stringp ins) (not (equal ins c)))
                              (setq node (append node (list :insert ins)))))
                          node))
                      (seq-take cands ebp-complete-max-candidates)))))))

(defun ebp-complete-in-text (document text cursor)
  "Complete DOCUMENT's TEXT at CURSOR (0-based Unicode scalar offset).
Replays TEXT into DOCUMENT's shadow buffer and harvests candidates
there.  Emacs characters ARE scalar values, so CURSOR maps to a buffer
position directly.  Returns (PREFIX . CANDIDATES) or nil.  Separated
from the seam function so tests can call it directly."
  (with-current-buffer (ebp-complete--shadow-buffer document)
    (erase-buffer)
    (insert text)
    (goto-char (min (1+ (max 0 (truncate cursor))) (point-max)))
    (ebp-complete--collect)))

;;;; The live-buffer arm (R0)

(defvar ebp-complete--live-harvest-active nil
  "Non-nil while a live-buffer harvest is on the stack.
Also bound by `ebp-sync--run-exit-fn' (R2) around a completion exit
function, which blocks the same way — the flag means \"a throw-armed
bounded wait inside wire-driven code\".  Read by two parties, both by
name only.  THIS module: a nested `edit.complete' dispatched while the
extent waits skips the live arm and answers from the shadow — two
stacked waits would share `with-timeout's macroexpansion-minted catch
tag, and the outer timer's throw would be stolen by the inner catch,
leaving the outer wait unbounded.  The JETPACS layer:
`jetpacs-flow-continue' postpones its continuations while this is up,
so a continuation that WAITS (a bridged prompt, hub.eval) is never on
the timeout throw's unwind path.")

(defvar ebp-complete-live-offer nil
  "The most recent live-buffer completion offer carrying an exit function.
A plist (:document D :editor-id E :buffer B :cursor C :prefix P
:exit-fn FN :accepts ALIST), ALIST mapping each candidate's INSERTED
text to its original propertized string (an exit function reads those
properties — eglot's LSP item above all).  Minted by the live harvest
when the winning capf supplied an `:exit-function'; consumed and
cleared by `ebp-sync''s splice watch, which recognizes the Companion's
accept — the wire deliberately does not mark one (SPEC 19.3: a tap is
an ordinary local edit) — and finishes the completion in the real
buffer, with every resulting edit riding the ordinary sync loop back
to the device.")

(defun ebp-complete--mint-offer (document editor-id buffer cursor result)
  "Record RESULT as the live accept offer for BUFFER, or clear it.
Only a harvest whose capf supplied an `:exit-function' mints one —
without it an accept needs no finishing, and the splice watch has
nothing to do."
  (setq ebp-complete-live-offer
        (when-let* ((result)
                    (extras ebp-complete--collect-extras)
                    (exit-fn (plist-get extras :exit-fn))
                    (raw (plist-get extras :raw)))
          (let (accepts)
            (dolist (cand (cdr result))
              (let* ((label (plist-get cand :label))
                     (ins (or (plist-get cand :insert) label))
                     (orig (cl-find-if
                            (lambda (r) (equal (substring-no-properties r)
                                               label))
                            raw)))
                (when orig (push (cons ins orig) accepts))))
            (when accepts
              (list :document document :editor-id editor-id
                    :buffer buffer :cursor (truncate cursor)
                    :prefix (car result) :exit-fn exit-fn
                    :accepts accepts))))))

(defun ebp-complete--live-harvest (document editor-id text cursor)
  "Harvest in DOCUMENT/EDITOR-ID's live attached buffer, if it can.
Returns (PREFIX . CANDIDATES), or nil to let the shadow answer: no
attached buffer (`ebp-sync' not loaded, document not synchronized), a
harvest already on the stack (`ebp-complete--live-harvest-active'),
buffer text diverged from the mirror TEXT (CURSOR addresses TEXT; a
buffer mid-flush holds different text and every offset would lie), the
harvest overran `ebp-complete-live-timeout' — or it simply found
nothing.  An empty live harvest is a fall-through, not an answer: the
shadow additionally carries `ebp-complete-shadow-setup-hook' sources
the live buffer never ran, and silencing those for attached documents
would break this module's own extension contract.

Point is moved under `save-excursion', and the harvest only reads — a
capf that mutates its buffer is broken everywhere, not just here.

Hazards of running capfs inside a jsonrpc REQUEST handler, bounded
rather than eliminated.  A blocking backend (an LSP server thinking)
is cut off by the timeout because its wait sits in
`accept-process-output', which runs timers — one spinning in C without
yielding is not cut off, the same limit `with-timeout' has everywhere.
While a backend waits, the ebp process filter may dispatch nested
work: an inbound `edit.delta' can move this very buffer under the
harvest, costing at worst a garbage offer the Companion's SPEC 19.3
selection gate discards; a nested `edit.complete' takes the shadow via
the latch above; and user-facing continuations are kept OFF this
extent entirely by `jetpacs-flow-continue's deferral, because the
timeout throw unwinding through a waiting prompt would abandon it
mid-round-trip."
  (when-let* ((buf (and (not ebp-complete--live-harvest-active)
                        (fboundp 'ebp-sync-attached-buffer)
                        (ebp-sync-attached-buffer document editor-id))))
    (let ((ebp-complete--live-harvest-active t))
      (with-current-buffer buf
        (save-excursion
          (save-restriction
            (widen)
            (when (equal text (buffer-substring-no-properties
                               (point-min) (point-max)))
              (goto-char (min (1+ (max 0 (truncate cursor))) (point-max)))
              (let ((r (with-timeout (ebp-complete-live-timeout nil)
                         (ebp-complete--collect))))
                (ebp-complete--mint-offer document editor-id
                                          (current-buffer) cursor r)
                r))))))))

;;;; The ebp seam

(defun ebp-complete-edit-complete (document editor-id text cursor)
  "Answer `edit.complete' for DOCUMENT (SPEC 19.3).
The `ebp-client-create' `:edit-complete-function' contract: called with
\(DOCUMENT EDITOR-ID TEXT CURSOR) only after ebp.el matched the query's
session and seq against the live mirror (a stale query was already
refused `1201 editor-stale', SPEC 19.3), TEXT the full mirror text.
Returns (PREFIX . CANDIDATES) or nil; ebp turns nil into the empty
reply, which is how the device clears its dropdown.

Dispatch order (R0): the live attached buffer when `ebp-sync' holds one
whose text matches the mirror — eglot and every buffer-local capf
answer there — falling through to DOCUMENT's shadow buffer whenever the
live arm cannot answer or finds nothing, exactly as before R0.

A harvest error also degrades to the empty reply — a broken capf must
cost a missing dropdown, never a `-32603' on the wire.  Install it at
connect time:
  (ebp-connect HOST PORT :edit-complete-function
               #\\='ebp-complete-edit-complete …)
Jetpacs's `jetpacs-connect' does exactly that by default."
  (when (and ebp-complete-enabled (stringp text) (numberp cursor))
    ;; A fresh request supersedes any standing accept offer: the
    ;; dropdown it described is being replaced.  The live harvest mints
    ;; the new one (or none).
    (setq ebp-complete-live-offer nil)
    (let ((result (condition-case err
                      (or (ebp-complete--live-harvest
                           document editor-id text cursor)
                          (ebp-complete-in-text document text cursor))
                    ;; The error SYMBOL only (SPEC 23.3):
                    ;; `error-message-string' embeds the datum, and the
                    ;; datum here is buffer content.
                    (error (message "ebp-complete: harvest failed (%s)"
                                    (car err))
                           nil))))
      (when ebp-complete-debug
        (if result
            (message "ebp-complete: %s prefix=%S -> %d candidate(s)"
                     document (car result) (length (cdr result)))
          (message "ebp-complete: %s -> nothing to offer at cursor"
                   document)))
      result)))

(provide 'ebp-complete)
;;; ebp-complete.el ends here
