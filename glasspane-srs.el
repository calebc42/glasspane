;;; glasspane-srs.el --- Spaced repetition over org-srs -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The Tier-1 skin for org-srs (docs/PLAN-glasspane-app.md, G7): a
;; pushed Review screen plus "Flashcard" on the heading detail view.
;;
;; Design — org-srs as an ENGINE, not a mirrored session.  The v1
;; ancestor of this file already learned the hard lesson: puppeteering
;; org-srs's live, window-centric review session produced broken cards
;; on the phone.  So org-srs runs entirely in the background and the
;; app renders its own clean cards:
;;   - The queue is `org-srs-review-pending-items' — the same set
;;     org-srs pulls each step; we show its first element and re-fetch
;;     after every rating, so `Again' cards reappear and the queue
;;     empties naturally.  No session, no continue-hook loop.
;;   - Rating is `org-srs-review-rate' with EXPLICIT item args — no
;;     window, no selected-buffer coupling.
;;   - Question/answer extraction is plain org per item type; reveal is
;;     a pure UI flag.
;;   - Undo keeps its own stack of log-drawer snapshots (org-srs's own
;;     undo history is only set up by the session we don't run).
;; Native-Emacs review coherence is a non-goal; everything degrades to
;; absent when org-srs isn't installed.
;;
;; Retired against v1 (the plan's retirement list + G7 section):
;; - The "glasspane.review" nav view, the drawer item, and its badge
;;   (S1): Review is a chrome screen behind `review.open'; the due
;;   count surfaces IN-SCREEN as the idle body's own content (the
;;   gap-#5 thread-through landed, but the app's ONE dock item wears
;;   the agenda count — a second number on the same icon is mud).
;; - `jetpacs-shell-push' handler tails and the `:switch-to' push: D2 —
;;   handlers answer a SPEC 14.4 status and refresh through
;;   `jetpacs-app-defer-refresh'.
;; - The `jetpacs-nav-item' toolbar chip: app-local text-button
;;   composition (T2), on a minted token instead of a baked ref (S5).
;; - `glasspane-srs--engine's swallow-and-notify: REWORKED — the macro
;;   now reports completion, and a failed engine call answers
;;   `rejected', never `accepted' (the G7 rung's named defect class).
;; - The load-time `with-eval-after-load' settings registration and
;;   refresh-hook lambda: both move behind `glasspane-srs-register'
;;   (the G0 gate contract), the settings block re-arming itself when
;;   the packages rung's install loads org-srs late.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-buffer)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'jetpacs-dialog)
(require 'jetpacs-settings)
(require 'glasspane-org)
(require 'glasspane-ui)

;; Same-rung sibling (G7): Review's stale-files half.  Soft — this
;; file must build and render with notes absent; the section then
;; simply isn't.
(require 'glasspane-notes nil t)
(declare-function glasspane-notes-stale-section "glasspane-notes" ())

;; org-srs is NOT installed locally: the `ext:' pseudo-file idiom
;; keeps byte-compile-error-on-warn honest with it absent, and every
;; call path hides behind `glasspane-srs-available-p'.
(declare-function org-srs-review-pending-items "ext:org-srs-review")
(declare-function org-srs-review-postpone "ext:org-srs-review")
(declare-function org-srs-review-rate "ext:org-srs-review-rate")
(declare-function org-srs-item-create "ext:org-srs-item")
(declare-function org-srs-item-marker "ext:org-srs-item")
(declare-function org-srs-item-call-with-current "ext:org-srs-item")
(declare-function org-srs-item-cloze-collect "ext:org-srs-item-cloze")
(declare-function org-srs-log-beginning-of-drawer "ext:org-srs-log")
(declare-function org-srs-log-end-of-drawer "ext:org-srs-log")
(declare-function org-srs-log-hide-drawer "ext:org-srs-log")
(declare-function org-srs-table-goto-column "ext:org-srs-table")
(declare-function org-srs-stats-intervals "ext:org-srs-stats-interval")
(declare-function org-srs-time-seconds-desc "ext:org-srs-time")

;; `org-srs-review-rate' reads this dynamic var to decide whether it is
;; mid-session; outside a session it is unbound, so we bind it to nil to
;; take the explicit-item-args path.  The bare defvar marks it special
;; so the `let' below binds dynamically even when byte-compiled without
;; org-srs loaded.
(defvar org-srs-review-item)

(defcustom glasspane-srs-source nil
  "The review scope: a file or directory org-srs reviews over.
nil means `org-directory' — review everything, the phone default."
  :type '(choice (const :tag "org-directory" nil) directory file)
  :group 'jetpacs)

(defvar glasspane-srs--available 'unknown
  "Cached org-srs availability; `unknown' re-probes on next ask.")

(defun glasspane-srs-available-p ()
  "Non-nil when org-srs is installed and loadable.
A failed probe is cached (a missing package must not re-scan the
load-path per render); pull-to-refresh re-probes, so installing
org-srs mid-session only needs a refresh."
  (when (eq glasspane-srs--available 'unknown)
    (setq glasspane-srs--available (and (require 'org-srs nil t) t)))
  glasspane-srs--available)

(defun glasspane-srs--reprobe ()
  "Forget the cached availability probe (the refresh-hook member)."
  (setq glasspane-srs--available 'unknown))

(defun glasspane-srs--source ()
  (or glasspane-srs-source org-directory))

;;;; Session state (S2 — the handlers below are the only writers)

(defvar glasspane-srs--active nil
  "Non-nil while a review is in progress on the phone.")

(defvar glasspane-srs--current nil
  "The item-args `(ITEM ID BUFFER)' under review, or nil.
Nil while a session is active means the queue drained (the done
screen); ITEM is `(card SIDE)' or `(cloze CLOZE-ID)'.")

(defvar glasspane-srs--revealed nil
  "Non-nil once the answer for `glasspane-srs--current' is shown.
A pure UI flag — the reveal never touches org-srs.")

(defvar glasspane-srs--undo nil
  "Stack of (ITEM-ARGS . LOG-STRING) snapshots for `srs.undo'.
Each entry is the item's SRSITEMS log-drawer text captured just
before that item was rated.")

;;;; The engine seam

(defmacro glasspane-srs--engine (&rest body)
  "Run BODY (org-srs engine calls) quietly; non-nil only when it completed.
Messages are suppressed so org-srs's and the user's `message's don't
surface as toasts; a signal becomes a snackbar (SPEC 23.3 label, the
raw text stays in *Messages*) and a nil return — the CALLER answers
`rejected' on nil, never `accepted' (the G7 rework: `accepted' means
durable, jetpacs-surfaces.el:918).  BODY's own value is discarded so a
nil-returning engine call can't read as failure."
  (declare (indent 0) (debug t))
  `(condition-case err
       (let ((inhibit-message t) (message-log-max nil))
         ,@body
         t)
     (error
      (message "glasspane: srs engine call failed: %s"
               (jetpacs-error-label err))
      (jetpacs-shell-notify (format "Review: %s" (jetpacs-error-label err)))
      nil)))

(defmacro glasspane-srs--quietly (&rest body)
  "Run BODY with messages suppressed, returning its value or nil on error.
The render-time counterpart of `glasspane-srs--engine': a failure while
building a view must NOT raise a snackbar (only actions do that)."
  (declare (indent 0) (debug t))
  `(let ((inhibit-message t) (message-log-max nil))
     (ignore-errors ,@body)))

(defun glasspane-srs--next-item ()
  "The first pending item over the source, or nil when none remain."
  (car (org-srs-review-pending-items (glasspane-srs--source))))

(defun glasspane-srs--advance ()
  "Load the next pending item and clear the reveal flag.
`--current' nil afterward means the queue drained."
  (setq glasspane-srs--current (glasspane-srs--quietly
                                 (glasspane-srs--next-item))
        glasspane-srs--revealed nil))

;;;; Due count (idle screen)

(defun glasspane-srs--due-count ()
  "Items a session over the configured source would show now, or nil.
Memoised through the org cache seam — every mutating srs.* action
invalidates, so the count follows ratings without a per-render scan."
  (when (glasspane-srs-available-p)
    (glasspane-srs--quietly
      (ebp-org-with-cache 'glasspane (list 'srs-due (glasspane-srs--source))
        (length (org-srs-review-pending-items (glasspane-srs--source)))))))

;;;; Content extraction & clean rendering

(defconst glasspane-srs--noise-drawers '("PROPERTIES" "SRSITEMS" "LOGBOOK")
  "Drawers hidden from the card renders: org metadata plus org-srs's
review log (`org-srs-log-drawer-name' is SRSITEMS).")

;; Card layouts are computed with plain org (not org-srs's region
;; helpers): under a subtree narrowing those helpers return
;; *entry*-scoped positions that collapse to empty answers.  This is
;; predictable and testable without org-srs installed.

(defun glasspane-srs--child-body (base title child-re)
  "Body region (BEG . END) of the direct child named TITLE, or nil.
BASE is the entry's outline level (point-min is its heading);
CHILD-RE matches level BASE+1 headings.  The region starts after the
child's own heading and meta-data, so it carries no `*' stars."
  (save-excursion
    (goto-char (point-min))
    (let (region)
      (while (and (not region) (re-search-forward child-re nil t))
        (goto-char (match-beginning 0))
        (when (and (eql (org-current-level) (1+ base))
                   (string-equal-ignore-case
                    (or (org-get-heading t t t t) "") title))
          (setq region
                (cons (save-excursion (org-end-of-meta-data t) (point))
                      (save-excursion (org-end-of-subtree t t) (point)))))
        (goto-char (match-end 0)))
      region)))

(defun glasspane-srs--card-parts (side)
  "Return (QUESTION . ANSWER) parts for the narrowed heading entry.
Each part is (title . STRING), (region BEG . END), or
\(title-and-region STRING BEG END).  SIDE is the reviewed (hidden
answer) side.  Handles the common heading-level layouts:
heading-as-front + body-as-back, explicit `Front'/`Back' children, and
Logseq-style nested block children."
  (goto-char (point-min))
  (let* ((base (or (org-current-level) 1))
         (title (or (org-get-heading t t t t) ""))
         (child-re (format "^\\*\\{%d\\}[ \t]" (1+ base)))
         (meta-end (save-excursion (goto-char (point-min))
                                   (org-end-of-meta-data t) (point)))
         (first-child (save-excursion
                        (goto-char meta-end)
                        (if (re-search-forward child-re nil t)
                            (line-beginning-position)
                          (point-max))))
         (front (glasspane-srs--child-body base "Front" child-re))
         (back (glasspane-srs--child-body base "Back" child-re))
         (front-face
          (cond (front (cons 'region front))
                ((< first-child (point-max))
                 ;; Has children: Front is title + body up to first-child.
                 (list 'title-and-region title meta-end first-child))
                (t (cons 'title title))))
         (back-face
          (cond (back (cons 'region back))
                ((< first-child (point-max))
                 ;; Has children: Back is the children.
                 (list 'region first-child (point-max)))
                (t
                 ;; No children: Back is the body.
                 (list 'region meta-end (point-max))))))
    (if (eq side 'front)
        (cons back-face front-face)
      (cons front-face back-face))))

(defun glasspane-srs--part-nodes (part)
  "Render a card PART: (title . STRING), (region BEG END), or
\(title-and-region STRING BEG END)."
  (pcase part
    (`(title . ,s)
     (and (stringp s) (not (string-empty-p s))
          (list (jetpacs-text s :style "title"))))
    (`(title-and-region ,title ,beg . ,rest)
     (let* ((end (if (consp rest) (car rest) rest))
            (title-nodes (and (stringp title) (not (string-empty-p title))
                              (list (jetpacs-text title :style "title"))))
            (jetpacs-line-numbers nil)
            (jetpacs-buffer-monospace nil)
            (region-nodes (when (and (integerp beg) (integerp end) (< beg end))
                            (jetpacs-buffer-render-region
                             (current-buffer) beg end))))
       (append title-nodes region-nodes)))
    (`(region ,beg . ,rest)
     (let ((end (if (consp rest) (car rest) rest))
           (jetpacs-line-numbers nil)
           (jetpacs-buffer-monospace nil))
       (when (and (integerp beg) (integerp end) (< beg end))
         (jetpacs-buffer-render-region (current-buffer) beg end))))
    (_ nil)))

(defun glasspane-srs--card-content (item revealed)
  "Question and (when REVEALED) answer nodes for a `card' ITEM.
ITEM is `(card SIDE)'; SIDE (default `back') is the hidden answer."
  (condition-case nil
      (let* ((parts (glasspane-srs--card-parts (or (cadr item) 'back)))
             (open (format "^[ \t]*:%s:[ \t]*$"
                           (regexp-opt glasspane-srs--noise-drawers)))
             (overlays nil)
             ;; Save the real buffer-local value so we can restore it.
             ;; setq, not let: `invisible-p' is a C function that reads
             ;; the buffer struct directly and never sees Lisp-level
             ;; dynamic bindings.
             (orig-invis-spec buffer-invisibility-spec))
        (unwind-protect
            (progn
              ;; A clean spec: remove fold-related entries so folded
              ;; body text renders.
              (setq buffer-invisibility-spec
                    (if (listp orig-invis-spec)
                        (cl-remove-if
                         (lambda (x)
                           (memq (if (consp x) (car x) x)
                                 '(outline org-fold-outline
                                   org-fold-drawer org-fold-block)))
                         orig-invis-spec)
                      orig-invis-spec))
              (add-to-invisibility-spec 'glasspane-srs-hide)
              ;; Hide noise drawers (PROPERTIES / SRSITEMS / LOGBOOK)
              ;; with our own overlays.
              (save-excursion
                (goto-char (point-min))
                (while (re-search-forward open nil t)
                  (let ((dbeg (match-beginning 0))
                        (dend (save-excursion
                                (and (re-search-forward
                                      "^[ \t]*:END:[ \t]*$" nil t)
                                     (min (1+ (line-end-position))
                                          (point-max))))))
                    (if (null dend)
                        (goto-char (line-end-position))
                      (let ((ov (make-overlay dbeg dend)))
                        (overlay-put ov 'invisible 'glasspane-srs-hide)
                        (push ov overlays)
                        (goto-char dend))))))
              ;; Hide org link brackets and targets with `display'
              ;; overlays: the buffer renderer skips a span whose
              ;; display property is the empty string
              ;; (jetpacs-buffer.el:580-582), which is more reliable
              ;; than `invisible' — the C-level `invisible-p' can be
              ;; disrupted by font-lock.
              (save-excursion
                (goto-char (point-min))
                ;; Descriptive links: [[target][description]]
                (while (re-search-forward
                        "\\[\\[\\([^]]*\\)\\]\\[\\([^]]*\\)\\]\\]" nil t)
                  (let ((ov1 (make-overlay (match-beginning 0)
                                           (match-beginning 2)))
                        (ov2 (make-overlay (match-end 2)
                                           (match-end 0))))
                    (overlay-put ov1 'display "")
                    (overlay-put ov2 'display "")
                    (push ov1 overlays)
                    (push ov2 overlays))))
              (save-excursion
                (goto-char (point-min))
                ;; Plain links: [[target]]
                (while (re-search-forward
                        "\\[\\[\\([^]]*\\)\\]\\]" nil t)
                  (let ((ov1 (make-overlay (match-beginning 0)
                                           (match-beginning 1)))
                        (ov2 (make-overlay (match-end 1)
                                           (match-end 0))))
                    (overlay-put ov1 'display "")
                    (overlay-put ov2 'display "")
                    (push ov1 overlays)
                    (push ov2 overlays))))
              (append
               (or (glasspane-srs--part-nodes (car parts))
                   (list (jetpacs-text "(no question)" :style "caption")))
               (when revealed
                 (cons (jetpacs-divider)
                       (or (glasspane-srs--part-nodes (cdr parts))
                           (list (jetpacs-text "(no answer)"
                                               :style "caption")))))))
          (setq buffer-invisibility-spec orig-invis-spec)
          (mapc #'delete-overlay overlays)))
    (error (list (jetpacs-text "Couldn't lay out this card."
                               :style "caption")))))

(defun glasspane-srs--cloze-content (item revealed)
  "Nodes for a `cloze' ITEM: the sentence with the reviewed blank.
ITEM is `(cloze CLOZE-ID)'.  The reviewed cloze shows as `[hint]' /
`[…]' until REVEALED; other clozes show their text as context.  Bounds
come from plain org; only `org-srs-item-cloze-collect' is org-srs."
  (condition-case nil
      (let* ((target (cadr item))
             (beg (save-excursion (goto-char (point-min))
                                  (org-end-of-meta-data t) (point)))
             (end (point-max))
             (clozes (sort (copy-sequence
                            (org-srs-item-cloze-collect beg end))
                           (lambda (a b) (< (cadr a) (cadr b)))))
             (pos beg) (parts nil))
        (dolist (cz clozes)
          (cl-destructuring-bind (id cbeg cend text &optional hint) cz
            (push (buffer-substring-no-properties pos cbeg) parts)
            (push (cond ((not (equal id target)) text)
                        (revealed text)
                        (t (format "[%s]" (or hint "…"))))
                  parts)
            (setq pos cend)))
        (push (buffer-substring-no-properties pos end) parts)
        (list (jetpacs-text (string-trim (apply #'concat (nreverse parts)))
                            :style "body")))
    (error (list (jetpacs-text "Couldn't lay out this cloze."
                               :style "caption")))))

(defun glasspane-srs--fallback-content ()
  "Render the narrowed entry cleanly for an unknown item type.
Drawers and gutter line numbers stripped; transient overlays only."
  (let ((jetpacs-line-numbers nil) (jetpacs-buffer-monospace nil)
        (overlays nil)
        (open (format "^[ \t]*:%s:[ \t]*$"
                      (regexp-opt glasspane-srs--noise-drawers))))
    (unwind-protect
        (progn
          (add-to-invisibility-spec 'glasspane-srs-hide)
          (save-excursion
            (goto-char (point-min))
            (while (re-search-forward open nil t)
              (let ((dbeg (match-beginning 0))
                    (dend (save-excursion
                            (and (re-search-forward
                                  "^[ \t]*:END:[ \t]*$" nil t)
                                 (min (1+ (line-end-position))
                                      (point-max))))))
                (if (null dend)
                    (goto-char (line-end-position))
                  (let ((ov (make-overlay dbeg dend)))
                    (overlay-put ov 'invisible 'glasspane-srs-hide)
                    (push ov overlays))
                  (goto-char dend)))))
          (jetpacs-buffer-render (current-buffer)))
      (mapc #'delete-overlay overlays)
      (remove-from-invisibility-spec 'glasspane-srs-hide))))

(defun glasspane-srs--item-nodes (item-args revealed)
  "Clean card nodes for ITEM-ARGS (`(ITEM ID BUFFER)'), REVEALED or not.
Resolves the item's marker in the background — no window, no session —
narrows to its entry, and dispatches on the item type."
  (let* ((item (car item-args))
         (type (car item))
         (marker (glasspane-srs--quietly
                   (apply #'org-srs-item-marker item-args))))
    (if (not (and (markerp marker) (marker-buffer marker)))
        (list (jetpacs-text "Couldn't load this card." :style "caption"))
      (with-current-buffer (marker-buffer marker)
        (save-excursion
          (save-restriction
            (widen)
            (goto-char marker)
            (org-back-to-heading-or-point-min)
            (unless (org-before-first-heading-p) (org-narrow-to-subtree))
            (pcase type
              ('card (glasspane-srs--card-content item revealed))
              ('cloze (glasspane-srs--cloze-content item revealed))
              (_ (glasspane-srs--fallback-content)))))))))

;;;; Rating chrome

(defconst glasspane-srs--ratings
  '(("again" :again "Again" "outlined")
    ("hard" :hard "Hard" "tonal")
    ("good" :good "Good" "filled")
    ("easy" :easy "Easy" "tonal"))
  "WIRE-NAME KEYWORD LABEL VARIANT rows for the rating buttons.")

(defun glasspane-srs--intervals ()
  "Predicted next intervals as a (:again SECS …) plist, or nil.
The org-srs-ui-mouse recipe, over the current item args: with point on
its log row and a `rating' column, the simulator runs."
  (when glasspane-srs--current
    (glasspane-srs--quietly
      (apply #'org-srs-item-call-with-current
             (lambda ()
               (when (org-srs-table-goto-column 'rating)
                 (org-srs-stats-intervals)))
             glasspane-srs--current))))

(defun glasspane-srs--format-interval (seconds)
  "SECONDS as a short \"3d 2h\" description (two components max)."
  (cl-loop for (amount unit . rest) on (org-srs-time-seconds-desc seconds)
           by #'cddr
           for i from 1
           concat (format "%d%.1s" amount
                          (string-trim-left (symbol-name unit) ":"))
           while (< i 2)
           when rest concat " "))

(defun glasspane-srs--rating-controls ()
  "The four rating buttons with predicted-interval captions."
  (let ((intervals (glasspane-srs--intervals)))
    (delq nil
          (list
           (when intervals
             (apply #'jetpacs-row
                    (mapcar (lambda (row)
                              (jetpacs-with-attrs
                               (jetpacs-box
                                (list (jetpacs-text
                                       (if-let* ((secs (plist-get
                                                        intervals
                                                        (cadr row))))
                                           (glasspane-srs--format-interval
                                            secs)
                                         "")
                                       :style "caption"))
                                :alignment "center")
                               :weight 1))
                            glasspane-srs--ratings)))
           (apply #'jetpacs-row
                  (mapcar (lambda (row)
                            (cl-destructuring-bind (name _kw label variant)
                                row
                              (jetpacs-with-attrs
                               (jetpacs-button
                                label
                                (jetpacs-action "srs.rate"
                                                :args (list :rating name))
                                :variant variant)
                               :weight 1)))
                          glasspane-srs--ratings))))))

;;;; The Review screen

(defun glasspane-srs--session-body ()
  "The active-session body: the card, then reveal or rating controls."
  (cond
   ((null glasspane-srs--current)
    (jetpacs-empty-state
     :icon "school" :title "All caught up"
     :caption "Review complete."
     :action-label "Done"
     :on-tap (jetpacs-action "srs.quit")))
   ((jetpacs-node-advertised-p "tabs")
    (glasspane-srs--session-pager))
   (t
    (apply #'jetpacs-lazy-column
           (append
            (glasspane-srs--item-nodes glasspane-srs--current
                                       glasspane-srs--revealed)
            (list (jetpacs-spacer :height 8) (jetpacs-divider))
            (if glasspane-srs--revealed
                (glasspane-srs--rating-controls)
              (list (jetpacs-button "Show answer"
                                    (jetpacs-action "srs.answer.show")
                                    :variant "filled"
                                    :icon "visibility"))))))))

(defun glasspane-srs--session-pager ()
  "Swipe-through review: the question page ‹ the answer page.
Both pages ship in one push — `glasspane-srs--item-nodes' is a pure
renderer over the item, so the answer costs no extra round-trip — and
the pager is id-keyed per item: rating pushes the next card, whose new
id lands the pager back on its question page; undo restores a card
answer-shown, so INITIAL follows the reveal flag.  on_change mirrors
the settled page into `glasspane-srs--revealed' without a re-push."
  (jetpacs-tabs
   (list (jetpacs-tab-item "Question") (jetpacs-tab-item "Answer"))
   (list
    (apply #'jetpacs-lazy-column
           (append
            (glasspane-srs--item-nodes glasspane-srs--current nil)
            (list (jetpacs-spacer :height 8)
                  (jetpacs-box
                   (list (jetpacs-text "Swipe for the answer ›"
                                       :style "caption"))
                   :alignment "center"))))
    (apply #'jetpacs-lazy-column
           (append
            (glasspane-srs--item-nodes glasspane-srs--current t)
            (list (jetpacs-spacer :height 8) (jetpacs-divider))
            (glasspane-srs--rating-controls))))
   :pager-only t
   :initial (if glasspane-srs--revealed 1 0)
   :id (format "srs-%x" (sxhash-equal glasspane-srs--current))
   :on-change (jetpacs-action "srs.answer.page")))

(defun glasspane-srs--idle-body ()
  "The between-sessions block: due summary and the start button.
The due count IS the retired drawer badge, surfaced in-screen — its
permanent home: the dock badge (gap #5, landed) carries the agenda
count, and two numbers on one icon is mud."
  (let ((due (glasspane-srs--due-count)))
    (cond
     ((null due)
      (jetpacs-column
       (jetpacs-text "Couldn't count due items — check *Messages*."
                     :style "caption")
       (jetpacs-button "Start review"
                       (jetpacs-action "srs.review.start")
                       :variant "filled" :icon "play_arrow")))
     ((zerop due)
      (jetpacs-empty-state :icon "school" :title "All caught up"
                           :caption "Nothing due right now."))
     (t
      (jetpacs-column
       (jetpacs-text (format "%d item%s due" due (if (= due 1) "" "s"))
                     :style "title")
       (jetpacs-spacer :height 8)
       (jetpacs-button "Start review"
                       (jetpacs-action "srs.review.start")
                       :variant "filled" :icon "play_arrow"))))))

(defun glasspane-srs--install-body ()
  "The org-srs-absent placeholder.
The install tap exists only while the packages rung's verb is live —
its handler-table entry is the capability probe, so the button never
dispatches into the action shim's `rejected'."
  (let ((installable (gethash "glasspane.packages.install"
                              jetpacs-action-handlers)))
    (jetpacs-empty-state
     :icon "school" :title "org-srs not installed"
     :caption "Install the org-srs engine, then pull to refresh."
     :action-label (when installable "Install engines")
     :on-tap (when installable
               (jetpacs-action "glasspane.packages.install")))))

(defun glasspane-srs--top-actions ()
  "Session top-bar actions — kept to the two that read at a glance:
undo (only after a rating) and close.  Postpone/suspend are niche and
their icons weren't legible; they stay as `srs.*' actions for a future
labelled menu rather than cluttering the bar."
  (delq nil
        (list
         (when glasspane-srs--undo
           (jetpacs-icon-button "undo"
                                (jetpacs-action "srs.undo")
                                :content-description "Undo last rating"))
         (jetpacs-icon-button "close"
                              (jetpacs-action "srs.quit")
                              :content-description "End review"))))

(defun glasspane-srs-stale-section ()
  "The notes sibling's stale-files block, or nil.
Same-rung sibling (G7), resolved at run time so this file stands
alone; an erroring section costs itself, never the Review screen."
  (and (fboundp 'glasspane-notes-stale-section)
       (condition-case nil (glasspane-notes-stale-section) (error nil))))

(defun glasspane-srs--review-body ()
  "The between-sessions Review body: flashcards, then vulpea stale files.
Stacked sections in one scroll — the flashcard half is small (a due
count and the start button), so both halves show at once.  Each half
degrades to its install prompt / to absent independently: org-srs
missing must not blank the stale list, nor vice versa."
  (let ((stale (glasspane-srs-stale-section)))
    (apply #'jetpacs-lazy-column
           (append
            (list (jetpacs-section-header "Flashcards")
                  (if (glasspane-srs-available-p)
                      (glasspane-srs--idle-body)
                    (glasspane-srs--install-body)))
            (when stale
              (cons (jetpacs-divider) stale))))))

(defun glasspane-srs-screen (back)
  "The pushed Review screen for the current session state."
  (jetpacs-chrome-screen
   "Review"
   (if glasspane-srs--active
       (glasspane-srs--session-body)
     (glasspane-srs--review-body))
   :back back
   :actions (when (and glasspane-srs--active glasspane-srs--current)
              (glasspane-srs--top-actions))))

;;;; Handlers (S4 — every one answers accepted/stale/rejected)

(defun glasspane-srs--on-open (_args params)
  "Push the Review screen onto the tapped surface."
  (let ((surface (or (plist-get params :surface)
                     (jetpacs-shell-surface-for "glasspane"))))
    (jetpacs-flow-continue
     (lambda ()
       ;; A deferred `jetpacs-chrome-push-screen' must catch its own
       ;; re-signal or a refused gate dies in a timer.
       (condition-case err
           (jetpacs-chrome-push-screen surface "glasspane-review"
                                       #'glasspane-srs-screen)
         (error (message "glasspane: review push failed: %s"
                         (jetpacs-error-label err))))))
    'accepted))

(defun glasspane-srs--on-review-start (_args params)
  "Begin a session: reset the undo stack and load the first card."
  (if (not (glasspane-srs-available-p))
      (progn
        (jetpacs-shell-notify "org-srs is not installed"
                              (plist-get params :surface))
        'rejected)
    (setq glasspane-srs--active t glasspane-srs--undo nil)
    (glasspane-srs--advance)
    (jetpacs-app-defer-refresh params)
    'accepted))

(defun glasspane-srs--on-answer-show (_args params)
  "Reveal the answer (the no-pager fallback's button)."
  (if (null glasspane-srs--current)
      'stale
    (setq glasspane-srs--revealed t)
    (jetpacs-app-defer-refresh params)
    'accepted))

(defun glasspane-srs--on-answer-page (args _params)
  "The review pager settled on a page; mirror it into the reveal flag.
No re-push (both pages already shipped) — just state coherence for
undo and the button-era code path."
  (let* ((idx (plist-get args :value))
         ;; A whole-valued integer can arrive as a float after the
         ;; JSON round trip (org.json emits the trailing .0).
         (idx (if (numberp idx) (truncate idx) idx)))
    (cond
     ((not (integerp idx)) 'rejected)
     ((null glasspane-srs--current) 'stale)
     (t
      (setq glasspane-srs--revealed (= idx 1))
      'accepted))))

(defun glasspane-srs--push-undo (item-args)
  "Snapshot ITEM-ARGS's log drawer onto the undo stack (capped).
Best-effort: a snapshot failure must not block the rating."
  (glasspane-srs--quietly
    (let ((marker (apply #'org-srs-item-marker item-args)))
      (with-current-buffer (marker-buffer marker)
        (org-with-wide-buffer
         (goto-char marker)
         (let ((log (buffer-substring-no-properties
                     (progn (org-srs-log-beginning-of-drawer) (point))
                     (progn (org-srs-log-end-of-drawer) (point)))))
           (push (cons item-args log) glasspane-srs--undo)
           (when (nthcdr 20 glasspane-srs--undo)
             (setcdr (nthcdr 19 glasspane-srs--undo) nil))))))))

(defun glasspane-srs--on-rate (args params)
  "Rate the current card and advance the queue."
  (let ((kw (cadr (assoc (plist-get args :rating) glasspane-srs--ratings))))
    (cond
     ((null kw) 'rejected)
     ((null glasspane-srs--current) 'stale)
     (t
      (let ((undo glasspane-srs--undo))
        (glasspane-srs--push-undo glasspane-srs--current)
        (if (not (glasspane-srs--engine
                   ;; `org-srs-review-rate' assumes a session: it reads
                   ;; a buffer-local schedule offset from
                   ;; `(current-buffer)', which the session normally
                   ;; makes the item's buffer.  Driving it in the
                   ;; background we set that up ourselves —
                   ;; current-buffer = the item's buffer, and
                   ;; `org-srs-review-item' nil so it rates the item
                   ;; passed in ARGS.  (Missed, the offset assert
                   ;; fails, the rating never persists, and the card
                   ;; loops forever.)
                   (let ((buf (marker-buffer
                               (apply #'org-srs-item-marker
                                      glasspane-srs--current)))
                         (org-srs-review-item nil))
                     (with-current-buffer buf
                       (apply #'org-srs-review-rate kw
                              glasspane-srs--current)
                       ;; Rating mutates the log drawer in the BUFFER
                       ;; only; without the save funnel the schedule
                       ;; dies with the process (the G9 device catch —
                       ;; the smoke loop's force-stop is any Android
                       ;; day's app kill).  Inside the engine form so a
                       ;; failed write answers `rejected', the
                       ;; suspend/undo shape.
                       (glasspane-org-save-and-invalidate)))))
            (progn
              ;; The rating never landed: its snapshot goes with it, or
              ;; the undo button would offer a no-op restore.
              (setq glasspane-srs--undo undo)
              'rejected)
          (glasspane-srs--advance)
          (jetpacs-app-defer-refresh params)
          'accepted))))))

(defun glasspane-srs--on-quit (_args params)
  "End the session; the screen re-renders as the between-sessions body."
  (setq glasspane-srs--active nil glasspane-srs--current nil
        glasspane-srs--revealed nil glasspane-srs--undo nil)
  (jetpacs-app-defer-refresh params)
  'accepted)

(defun glasspane-srs--on-postpone (_args params)
  "Push the current card a day out and advance."
  (cond
   ((null glasspane-srs--current) 'stale)
   ((not (glasspane-srs--engine
           (let ((marker (apply #'org-srs-item-marker
                                glasspane-srs--current)))
             (with-current-buffer (marker-buffer marker)
               (apply #'org-srs-review-postpone '(1 :day)
                      glasspane-srs--current)
               ;; Same durability rule as rate: the pushed-out
               ;; schedule exists only in the buffer until saved.
               (glasspane-org-save-and-invalidate)))))
    'rejected)
   (t
    (glasspane-srs--advance)
    (jetpacs-app-defer-refresh params)
    'accepted)))

(defun glasspane-srs--on-suspend (_args params)
  "Suspend the current card: comment its heading out of the queue."
  (cond
   ((null glasspane-srs--current) 'stale)
   ((not (glasspane-srs--engine
           (let ((marker (apply #'org-srs-item-marker
                                glasspane-srs--current)))
             (with-current-buffer (marker-buffer marker)
               (org-with-wide-buffer
                (goto-char marker)
                (org-back-to-heading t)
                (unless (org-in-commented-heading-p)
                  (org-toggle-comment))
                (glasspane-org-save-and-invalidate))))))
    'rejected)
   (t
    (glasspane-srs--advance)
    (jetpacs-app-defer-refresh params)
    'accepted)))

(defun glasspane-srs--on-undo (_args params)
  "Restore the last-rated item's log drawer from our snapshot.
org-srs's own undo history exists only inside the session we never
run.  The card re-presents answer-shown for a fresh rating; the
snapshot pops only after the restore LANDS — a failed write keeps it
for the retry."
  (let ((snap (car glasspane-srs--undo)))
    (cond
     ((null snap)
      (jetpacs-shell-notify "Nothing to undo" (plist-get params :surface))
      'stale)
     ((not (glasspane-srs--engine
             (let* ((item-args (car snap))
                    (marker (apply #'org-srs-item-marker item-args)))
               (with-current-buffer (marker-buffer marker)
                 (org-with-wide-buffer
                  (goto-char marker)
                  (delete-region
                   (progn (org-srs-log-beginning-of-drawer) (point))
                   (progn (org-srs-log-end-of-drawer) (point)))
                  (insert (cdr snap))
                  (org-srs-log-hide-drawer)
                  (glasspane-org-save-and-invalidate))))))
      'rejected)
     (t
      (pop glasspane-srs--undo)
      (setq glasspane-srs--current (car snap)
            glasspane-srs--revealed t)
      (jetpacs-app-defer-refresh params)
      'accepted))))

;;;; Authoring: Flashcard on the heading detail view

(defun glasspane-srs--create-flow (args params)
  "Run org-srs's prompting create for ARGS' token (outside dispatch, D2).
The type picker and any follow-up prompts arrive as phone dialogs
through the minibuffer bridge — written as if at the keyboard; the
headless refusal is mandatory (the JA-6 P2 lesson)."
  (let ((surface (plist-get params :surface)))
    (if (not (jetpacs-dialog-can-bridge-p))
        (jetpacs-shell-notify
         (if (bound-and-true-p jetpacs-dialog--pending)
             "Busy — finish the open dialog first"
           "This needs the Companion dialog bridge")
         surface)
      ;; `glasspane-ui-at-ref' owns resolve/classify/save; its error
      ;; arm already toasts.  Only the bridged prompt's C-g needs a
      ;; home here — `quit' is not an `error' and would otherwise die
      ;; in the timer.
      (condition-case nil
          (when (eq (glasspane-ui-at-ref
                     args (lambda () (org-srs-item-create)) t)
                    'accepted)
            (jetpacs-shell-notify "Review item created" surface))
        (quit (jetpacs-shell-notify "Cancelled" surface)))
      (ignore-errors (jetpacs-shell-push surface)))))

(defun glasspane-srs--on-item-create (args params)
  "Make the tokened heading reviewable via org-srs's own create flow.
Validates in the dispatch extent, answers, and defers the prompting
create (S4: deferred work returns `accepted' immediately)."
  (cond
   ((not (stringp (plist-get args :token))) 'rejected)
   ((null (ebp-org-token-ref (plist-get args :token) :owner "glasspane"))
    'stale)
   ((not (glasspane-srs-available-p))
    (jetpacs-shell-notify "org-srs is not installed"
                          (plist-get params :surface))
    'rejected)
   (t
    (jetpacs-flow-continue
     (lambda () (glasspane-srs--create-flow args params)))
    'accepted)))

(defun glasspane-srs-detail-toolbar (ref)
  "The detail floating-toolbar chip for REF: make this heading reviewable.
The token joins detail's mint discipline (S5): minted at render into
this module's own single-ref set — the replace sweep retires the
previous detail screen's chip, so a stale tap answers `stale'.
Best-effort like detail's archive token: an unmintable ref just costs
the chip."
  (when (glasspane-srs-available-p)
    (condition-case nil
        (let ((token (car (ebp-org-ref-tokens (list ref)
                                              :set "srs-detail"
                                              :owner "glasspane"))))
          (list (jetpacs-button "Flashcard"
                                (jetpacs-action "srs.item.create"
                                                :args (list :token token))
                                :icon "school" :variant "text")))
      (error nil))))

;;;; Settings

(defun glasspane-srs--settings-section-maybe ()
  "Register the Review settings block once BOTH halves exist.
Runs from `glasspane-srs-register' and again when org-srs loads late
\(the packages rung's mid-session install): the entries name org-srs
defcustoms, so the section must never register while they are
unbound — and never while the app itself is unregistered, which is
what keeps the load-time `with-eval-after-load' below inside the
register/unregister sweep."
  (when (and (featurep 'org-srs)
             (gethash "srs.rate" jetpacs-action-handlers))
    (jetpacs-settings-register-section
     "Review"
     '((org-srs-review-new-items-per-day :label "New cards per day")
       (org-srs-review-max-reviews-per-day :label "Max reviews per day")))))

;; The form outlives the feature: M-x unload-feature voids the symbol
;; while this closure is still on org-srs's after-load list, so a later
;; (require 'org-srs) would signal void-function inside org-srs's OWN
;; load.  It stays top-level — the docstring above names this
;; late-install path, which `glasspane-srs-register' cannot reach.
(with-eval-after-load 'org-srs
  (when (fboundp 'glasspane-srs--settings-section-maybe)
    (glasspane-srs--settings-section-maybe)))

;;;; Registration

(defconst glasspane-srs--verbs
  '("review.open"
    "srs.review.start"
    "srs.answer.show"
    "srs.answer.page"
    "srs.rate"
    "srs.quit"
    "srs.postpone"
    "srs.suspend"
    "srs.undo"
    "srs.item.create")
  "The verbs this module owns, for the register/unregister sweep.")

(defun glasspane-srs-register ()
  "Register the review verbs, the detail chip, and the settings block.
Called from `glasspane-register', not at this file's load (the G0
gate contract).  Idempotent: re-registration replaces handlers in
place and the hooks add exactly once."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "review.open" #'glasspane-srs--on-open
                       :doc "Push the Review screen")
    (jetpacs-defaction "srs.review.start" #'glasspane-srs--on-review-start
                       :doc "Begin a review session over the source")
    (jetpacs-defaction "srs.answer.show" #'glasspane-srs--on-answer-show
                       :doc "Reveal the current card's answer")
    (jetpacs-defaction "srs.answer.page" #'glasspane-srs--on-answer-page
                       :doc "Mirror the review pager's settled page")
    (jetpacs-defaction "srs.rate" #'glasspane-srs--on-rate
                       :doc "Rate the current card and advance")
    (jetpacs-defaction "srs.quit" #'glasspane-srs--on-quit
                       :doc "End the review session")
    (jetpacs-defaction "srs.postpone" #'glasspane-srs--on-postpone
                       :doc "Postpone the current card a day")
    (jetpacs-defaction "srs.suspend" #'glasspane-srs--on-suspend
                       :doc "Suspend the current card (COMMENT heading)")
    (jetpacs-defaction "srs.undo" #'glasspane-srs--on-undo
                       :doc "Undo the last rating from the app's snapshot")
    (jetpacs-defaction "srs.item.create" #'glasspane-srs--on-item-create
                       :doc "Make a heading reviewable (bridged prompts)"))
  (add-hook 'glasspane-ui-detail-toolbar-functions
            #'glasspane-srs-detail-toolbar)
  (add-hook 'jetpacs-shell-refresh-hook #'glasspane-srs--reprobe)
  (glasspane-srs--settings-section-maybe))

(defun glasspane-srs-unregister ()
  "Drop the review verbs, the chip, the hooks, and the settings block.
The session dies with the registration: a re-register starts from no
session rather than resuming the one whose verbs just went away."
  (dolist (name glasspane-srs--verbs)
    (jetpacs-undefaction name))
  (remove-hook 'glasspane-ui-detail-toolbar-functions
               #'glasspane-srs-detail-toolbar)
  (remove-hook 'jetpacs-shell-refresh-hook #'glasspane-srs--reprobe)
  (setq glasspane-srs--active nil glasspane-srs--current nil
        glasspane-srs--revealed nil glasspane-srs--undo nil)
  (jetpacs-settings-remove-section "Review"))

(provide 'glasspane-srs)
;;; glasspane-srs.el ends here
