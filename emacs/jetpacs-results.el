;;; jetpacs-results.el --- Generic results/loci navigator (Tier 0.5) -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Tier 0.5: the `next-error' protocol is the substrate under every
;; "list of loci -> jump into a source buffer" mode — occur, grep/rgrep and
;; compilation (grep-mode derives from compilation-mode, so it is covered
;; for free), xref, and anything built on them.  ONE skin renders them all
;; as tappable cards, the same bet `jetpacs-tablist' makes on
;; tabulated-list-mode.
;;
;; Under the Tier 0 renderer these buffers already render and their rows
;; are already tappable — but a tap runs the mode's own visit command,
;; which pops a *desktop* window and leaves the phone on the results
;; buffer.  This substrate re-points the tap at the phone: it follows the
;; locus and shows the source location, framed around the hit.
;;
;; Two producers feed one visit/stepper seam:
;;   * buffer-loci — a position in a results buffer whose own goto command
;;     jumps to source (occur/compilation/xref); addressed by (buffer, pos).
;;   * file-loci  — a plain (file, line) set handed in by a server-side
;;     search through `jetpacs-results-set-file-loci'; addressed by INDEX,
;;     so no path ever travels over the wire.
;;
;; The visit parses no mode internals: place point on the locus row, run
;; the row's own RET/mouse-2 binding with the buffer-display functions
;; shimmed so nothing pops a desktop window, and read where point lands.
;;
;; Rung JC-2 of docs/PLAN-jetpacs-consumers.md.  Ported from poc-v1 with
;; the format-6 drift applied and three conformance changes the rewrite
;; requires:
;;
;; - Every action derives a SPEC 14.4 status.  In particular a `pos' that
;;   names no current locus is `stale', not a silent visit of row 0 — the
;;   row moved since the snapshot the user tapped (SPEC 14.5).
;; - Tap targets are recorded in JC-1's exposure table (SPEC 23.1), so a
;;   buffer/offset off the wire can only ever drive a locus this Emacs
;;   actually rendered.
;; - Optional node types degrade to the Core Node Set when the Companion
;;   does not advertise them (SPEC 16.2).

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)   ; jetpacs-defaction / jetpacs-client
(require 'jetpacs-buffer)     ; jetpacs-render-buffer-register, exposure table

;; --- Configuration and host seam --------------------------------------------

(defcustom jetpacs-results-max-loci 300
  "Maximum locus cards rendered from one results buffer.
A huge grep/compilation buffer is capped with a trailing note; the count
in the header still reflects the true total."
  :type 'integer :group 'jetpacs)

(defcustom jetpacs-results-context-lines 100
  "Lines of source context shown below a visited locus."
  :type 'integer :group 'jetpacs)

(defcustom jetpacs-results-context-before 20
  "Lines of source context shown above a visited locus."
  :type 'integer :group 'jetpacs)

(defvar jetpacs-results--region nil
  "The region the last visit framed, or nil.
A plist (:buffer NAME :beg B :end E :label L :point P).  Rendered by
`jetpacs-results-region-nodes', which a host root includes.")

(defvar jetpacs-results-event-surface nil
  "The surface the in-flight visit/step event came from, or nil.
Bound by the actions around their effect.  These actions register
OWNERLESS, so `jetpacs--dispatch' binds no owner for them and a zero-arg
re-push still resolves to `jetpacs-shell-surface-id' — a surface the
user is not looking at.  (The dispatch DOES bind the registering owner
now, but only for an action claimed under `with-jetpacs-owner'; an
ownerless one like these has nothing to recover.)")

(defvar jetpacs-results-visit-region-function
  #'jetpacs-results-show-region
  "Function of (BUFFER-NAME BEG END LABEL &optional POINT) showing a slice
with POINT's line as the scroll target.  The default records the region
and re-pushes the current surface, so a host root that includes
`jetpacs-results-region-nodes' shows it; a richer host may replace it.")

(defvar jetpacs-results--nav nil
  "The active locus-stepper context, or nil.
A plist (:kind KIND :index I :count N :dest SRC-NAME) plus the
kind-specific step source — :buffer RESULTS-NAME for `buffer', :loci
FILE-LOCI for `file'.")

(defvar jetpacs-results--file-set nil
  "The active file-locus result set, or nil.
A list of plists (:file PATH :line N :text STRING).  Cards tap
`results.visit' with their INDEX into this list; no path crosses the wire.")

(defun jetpacs-results-set-file-loci (loci)
  "Store LOCI as the active file-locus result set for `results.visit'."
  (setq jetpacs-results--file-set loci))

;; compilation-mode covers grep-mode, rgrep, and every
;; `define-compilation-mode' derivative by derivation.  This list also
;; GATES the visit action: a buffer name off the wire can only ever reach
;; a buffer that really is one of these results modes (SPEC 23.1).
(defconst jetpacs-results-modes
  '(occur-mode compilation-mode xref--xref-buffer-mode)
  "Major modes rendered and visited as loci by this substrate.")

(defun jetpacs-results--buffer-p (buf)
  "Non-nil when BUF is live and one of `jetpacs-results-modes'."
  (and (buffer-live-p buf)
       (with-current-buffer buf
         (derived-mode-p jetpacs-results-modes))))

;; --- Reading the loci --------------------------------------------------------

(defun jetpacs-results--locus-pos (bol eol)
  "Return the position on line [BOL, EOL) carrying a jump, or nil.
Generic across the family: occur marks matches with `occur-target',
compilation with `compilation-message', xref rows are buttons, and any
mode may carry a `mouse-face' or text-property keymap.  Checks the line
start first, then the first non-blank char."
  (cl-flet ((jump-at (p)
              (and (< p eol)
                   (or (get-text-property p 'occur-target)
                       (get-text-property p 'compilation-message)
                       (get-text-property p 'xref-item)
                       (get-char-property p 'button)
                       (get-char-property p 'mouse-face)
                       (let ((km (or (get-char-property p 'keymap)
                                     (get-char-property p 'local-map))))
                         (and (keymapp km)
                              (or (lookup-key km (kbd "RET"))
                                  (lookup-key km [return])
                                  (lookup-key km [mouse-2]))))))))
    (cond
     ((jump-at bol) bol)
     (t (let ((p (save-excursion
                   (goto-char bol)
                   (skip-chars-forward " \t" eol)
                   (point))))
          (and (> p bol) (jump-at p) p))))))

(defun jetpacs-results--loci (buf &optional limit)
  "Collect (POS . TEXT) for each locus row of results buffer BUF.
Walking the printed buffer respects the mode's current ordering.  Stops
after LIMIT loci (default `jetpacs-results-max-loci'): the scan bound and
the render cap MUST be the same number, or the stepper reports a count
covering loci that were never rendered — and so were never exposed, so
stepping into them is refused (SPEC 23.1).  It also keeps an enormous
grep buffer from being walked whole inside the dispatch extent."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (let ((limit (or limit jetpacs-results-max-loci))
            (n 0)
            loci)
        (while (and (not (eobp)) (< n limit))
          (let* ((bol (line-beginning-position))
                 (eol (line-end-position))
                 (pos (and (> eol bol) (jetpacs-results--locus-pos bol eol))))
            (when pos
              ;; SPEC 4.1: a results line is arbitrary buffer text and may
              ;; hold undecodable octets (a grep over a latin-1 or binary
              ;; file), which are not Unicode scalar values and which
              ;; `json-serialize' rejects outright — taking the whole push
              ;; down.  Same sanitizer the Tier-0 renderer uses.
              (push (cons pos (jetpacs-buffer-scalar-text
                               (string-trim
                                (buffer-substring-no-properties bol eol))))
                    loci)
              (setq n (1+ n))))
          (forward-line 1))
        (nreverse loci)))))

(defun jetpacs-results--index-of (loci pos)
  "Index in LOCI of the locus at POS, or nil when POS names none.
nil is the honest answer and the caller answers `stale' (SPEC 14.5): the
poc returned 0, silently visiting a different row than the user tapped."
  (cl-position pos loci :key #'car :test #'=))

;; --- Rendering ---------------------------------------------------------------

(defun jetpacs-results--card (name pos text)
  "A tappable card for the locus at POS in results buffer NAME.
Records POS in the exposure table: this skin builds its own rows instead
of walking the Tier-0 renderer, so nothing else would make POS a
legitimate tap target (SPEC 23.1)."
  (jetpacs-buffer-expose name pos "results.visit")
  (let* ((label (if (string-empty-p text) " " text))
         (action (jetpacs-action "results.visit"
                                 :args (list :buffer name :pos pos)))
         ;; `card' and `rich_text' are OPTIONAL (SPEC 16.2's Core Node Set
         ;; is text/row/column/box/spacer/divider/button/text_input), so
         ;; degrade rather than emit a type the Companion never advertised.
         (body (if (jetpacs-node-advertised-p "rich_text")
                   (jetpacs-rich-text (list (jetpacs-span label :mono t)))
                 (jetpacs-text label :style "mono")))
         (row (if (jetpacs-node-advertised-p "icon")
                  (jetpacs-row (jetpacs-with-attrs (jetpacs-box body) :weight 1)
                               (jetpacs-icon "chevron_right"))
                (jetpacs-with-attrs (jetpacs-box body) :weight 1))))
    (if (jetpacs-node-advertised-p "card")
        (jetpacs-card row :on-tap action)
      ;; A Core `button' keeps the row tappable when `card' is absent.
      (jetpacs-column row (jetpacs-button label action)))))

(defun jetpacs-results-render (buf)
  "Tier-1 skin: results BUF as a count header plus one card per locus.
Returns a list of nodes, per the `jetpacs-render-buffer' contract."
  (with-current-buffer buf
    (let* ((name (buffer-name buf))
           ;; Scan one past the cap so "showing N of M+" is honest without
           ;; walking a huge buffer to the end.
           (probe (jetpacs-results--loci buf (1+ jetpacs-results-max-loci)))
           (capped (> (length probe) jetpacs-results-max-loci))
           (shown (if capped (cl-subseq probe 0 jetpacs-results-max-loci)
                    probe))
           (total (length shown)))
      (if (null shown)
          ;; No parsed loci — the mode may be mid-run (an empty *grep*) or
          ;; nothing matched.  Fall back to faithful Tier 0 text so the
          ;; buffer is never blank.
          (jetpacs-buffer-render buf)
        ;; This render supersedes the last one for this buffer: only the
        ;; positions emitted below stay tappable.
        (jetpacs-buffer-forget-exposed name)
        (append
         (list (jetpacs-text
                (format "%d result%s%s" total (if (= total 1) "" "s")
                        (if capped "+" ""))
                :style "caption"))
         (mapcar (lambda (l) (jetpacs-results--card name (car l) (cdr l)))
                 shown)
         (when capped
           (list (jetpacs-text
                  (format "Showing the first %d — narrow the search." total)
                  :style "caption"))))))))

(dolist (mode jetpacs-results-modes)
  (jetpacs-render-buffer-register mode #'jetpacs-results-render))

;; --- The region view ---------------------------------------------------------

(defun jetpacs-results-show-region (name beg end label &optional point)
  "Record the slice [BEG, END) of buffer NAME and re-push (the default seam).
LABEL heads the slice; POINT's line is the scroll target.  Re-pushes the
surface the event came from (`jetpacs-results-event-surface'), not the
ambient default: a handler runs outside any owner scope, so a zero-arg
push would refresh the wrong surface under decision D1."
  (setq jetpacs-results--region
        (list :buffer name :beg beg :end end :label label :point point))
  ;; Re-push through JC-1's seam (which `jetpacs-shell' wires to
  ;; `jetpacs-shell-push'), so this module needs no dependency on the
  ;; shell — and DEFER it: `jetpacs-shell-push' SIGNALS on any gate
  ;; failure, and a signal here would escape after the jump already
  ;; landed, answering `rejected' for an effect that happened and leaving
  ;; the stepper armed on a view that never opened.
  (let ((surface jetpacs-results-event-surface))
    (run-at-time 0 nil
                 (lambda ()
                   (when (functionp jetpacs-buffer-refresh-function)
                     (condition-case err
                         (funcall jetpacs-buffer-refresh-function surface)
                       (error
                        (message "jetpacs-results: region push failed: %s"
                                 (jetpacs--error-label err)))))))))

(defun jetpacs-results-region-nodes ()
  "Nodes for the last visited region, or nil when none is armed.
A host root includes this to show where a `results.visit' landed."
  (when-let* ((r jetpacs-results--region)
              (buf (get-buffer (plist-get r :buffer))))
    (append
     (list (jetpacs-text (plist-get r :label) :style "label"))
     (jetpacs-results-buffer-view-actions (plist-get r :buffer))
     (jetpacs-buffer-render-region buf (plist-get r :beg) (plist-get r :end)
                                   (plist-get r :point)))))

(defun jetpacs-results-region-buffer ()
  "The buffer NAME the armed region view addresses, or nil.
A host presenting several buffers (the JA-3 chrome stack) shows the
region nodes only on the screen of the buffer they belong to; without
this reader it would have to reach for the private variable."
  (plist-get jetpacs-results--region :buffer))

(defun jetpacs-results-clear-region ()
  "Disarm the region view; the next render shows the whole buffer.
Public because the region is shared state: the imenu navigation (JA-3)
arms it through `jetpacs-results-show-region' and needs a sanctioned
way to dismiss it without reaching for the private variable."
  (setq jetpacs-results--region nil))

(defun jetpacs-results-region-around (buf pos)
  "Return (BEG END LABEL POINT) framing POS in BUF for the region view."
  (with-current-buffer buf
    (save-excursion
      (goto-char (min (max (point-min) pos) (point-max)))
      (let* ((line (line-number-at-pos))
             (target (line-beginning-position))
             (beg (save-excursion
                    (forward-line (- jetpacs-results-context-before)) (point)))
             (end (save-excursion
                    (forward-line (1+ jetpacs-results-context-lines)) (point))))
        (list beg end (format "%s:%d" (buffer-name buf) line) target)))))

;; --- Visiting a locus --------------------------------------------------------

(defun jetpacs-results-visit-command (pos)
  "The visit command for the locus at POS: text-prop keymap, else major map."
  (let ((km (or (get-char-property pos 'keymap)
                (get-char-property pos 'local-map))))
    (or (and (keymapp km)
             (or (lookup-key km (kbd "RET"))
                 (lookup-key km [return])
                 (lookup-key km [mouse-2])))
        (let ((maj (current-local-map)))
          (and maj
               (or (lookup-key maj (kbd "RET"))
                   (lookup-key maj [return])
                   (lookup-key maj [mouse-2])))))))

(defun jetpacs-results-follow (buf pos)
  "Follow the locus at POS in results BUF; return (DEST-BUF . DEST-POS) or nil.
Runs the row's own goto command through `jetpacs-buffer-call-shimmed', so
nothing pops a desktop window and a stale input event cannot hijack the
jump.  Returns nil when the command never left the results buffer, and
SIGNALS when the command itself failed — the shim swallows the error and
still hands back `(current-buffer) . (point)', so without the ON-ERROR
thunk a failed goto is indistinguishable from having stayed put, and the
handler answers `accepted' for a visit that never happened."
  (with-current-buffer buf
    (goto-char (min (max (point-min) pos) (point-max)))
    (let ((cmd (jetpacs-results-visit-command (point))))
      (when (commandp cmd)
        (let* ((failed nil)
               (dest (jetpacs-buffer-call-shimmed
                      cmd (lambda (err) (setq failed err))))
               (dest-buf (car dest)))
          (when failed (signal (car failed) (cdr failed)))
          (and dest-buf (not (eq dest-buf buf)) dest))))))

(defun jetpacs-results--show (dest index count nav-extra)
  "Open DEST (a (BUFFER . POS) pair) in the region view; arm the stepper."
  (pcase-let ((`(,beg ,end ,label ,point)
               (jetpacs-results-region-around (car dest) (cdr dest))))
    (setq jetpacs-results--nav
          (append (list :index index :count count :dest (buffer-name (car dest)))
                  nav-extra))
    (funcall jetpacs-results-visit-region-function
             (buffer-name (car dest)) beg end
             (format "%s  ·  %d/%d" label (1+ index) count)
             point)
    t))

(defun jetpacs-results--goto-buffer (results-buf loci index)
  "Visit buffer-locus LOCI[INDEX] of RESULTS-BUF; arm a `buffer'-kind nav."
  (let* ((count (length loci))
         (index (max 0 (min index (1- count))))
         (pos (car (nth index loci)))
         (dest (and pos (ignore-errors
                          (jetpacs-results-follow results-buf pos)))))
    (when dest
      (jetpacs-results--show dest index count
                             (list :kind 'buffer
                                   :buffer (buffer-name results-buf))))))

(defun jetpacs-results--file-dest (locus)
  "Resolve a file LOCUS (:file :line) to (BUFFER . POS), or nil."
  (let ((file (plist-get locus :file))
        (line (plist-get locus :line)))
    (when (and (stringp file) (file-readable-p file))
      (condition-case nil
          (let ((buf (find-file-noselect file)))
            (with-current-buffer buf
              (save-excursion
                (goto-char (point-min))
                (forward-line (1- (max 1 (truncate (or line 1)))))
                (cons buf (point)))))
        (error nil)))))

(defun jetpacs-results--goto-file (loci index)
  "Visit file-locus LOCI[INDEX]; arm a `file'-kind nav.  INDEX is clamped."
  (let* ((count (length loci))
         (index (max 0 (min index (1- count))))
         (dest (jetpacs-results--file-dest (nth index loci))))
    (when dest
      (jetpacs-results--show dest index count (list :kind 'file :loci loci)))))

;; --- Actions -----------------------------------------------------------------
;;
;; Both run their effect SYNCHRONOUSLY, so `accepted' names a completed
;; jump (SPEC 14.4: "Returning `accepted' merely because a volatile
;; callback was scheduled is not conforming"); the re-push rides the
;; visit-region seam.  Neither prompts, so neither blocks the dispatch
;; extent (decision D2).

(jetpacs-defaction "results.visit"
  ;; Two entry shapes:
  ;;   (:buffer NAME :pos P) — a results-mode buffer's own goto at P.
  ;;   (:index I)            — entry I of the active file-locus set.
  (lambda (args params)
    (let ((buf-name (plist-get args :buffer))
          (pos (plist-get args :pos))
          (index (plist-get args :index))
          (jetpacs-results-event-surface (plist-get params :surface)))
      (cond
       ((and (stringp buf-name) (numberp pos))
        (let ((buf (get-buffer buf-name)))
          (cond
           ;; SPEC 23.1: only a buffer this Emacs actually rendered as a
           ;; results list, at an offset it actually offered.
           ((not (jetpacs-results--buffer-p buf)) 'rejected)
           ((not (jetpacs-buffer-exposed-p buf-name pos "results.visit"))
            'rejected)
           ((jetpacs-event-stale-p params) 'stale)
           (t
            (let* ((loci (jetpacs-results--loci buf))
                   (i (and loci (jetpacs-results--index-of loci pos))))
              (cond
               ((null loci) 'rejected)
               ;; SPEC 14.5: the row the user tapped is no longer at that
               ;; offset — the list moved under them.  `stale' lets the
               ;; Companion re-present; visiting row 0 instead (what the
               ;; poc did) silently jumps somewhere they did not ask for.
               ((null i) 'stale)
               ((jetpacs-results--goto-buffer buf loci i) 'accepted)
               (t 'rejected)))))))
       ((numberp index)
        (let ((set jetpacs-results--file-set))
          (cond
           ((not (and set (>= index 0) (< index (length set)))) 'stale)
           ((jetpacs-results--goto-file set index) 'accepted)
           (t 'rejected))))
       (t 'rejected)))))

(jetpacs-defaction "results.step"
  ;; Step to the prev/next locus of the armed set without returning to the
  ;; list.  DIR is +1 or -1.  Buffer-kind loci are recomputed each step (a
  ;; reverted results buffer still steps sanely); file-kind loci step over
  ;; the snapshot armed at visit time.
  (lambda (args params)
    (let* ((nav jetpacs-results--nav)
           (dir (plist-get args :dir))
           (jetpacs-results-event-surface (plist-get params :surface)))
      (if (not (and nav (numberp dir) (memq dir '(-1 1))))
          'rejected
        (let ((target (+ (plist-get nav :index) dir)))
          (pcase (plist-get nav :kind)
            ('buffer
             (let ((buf (get-buffer (plist-get nav :buffer))))
               (if (not (jetpacs-results--buffer-p buf))
                   ;; The result set is gone: the stepper is meaningless
                   ;; now, so disarm and report a permanently dead context.
                   (progn (setq jetpacs-results--nav nil) 'stale)
                 (let ((loci (jetpacs-results--loci buf)))
                   (cond
                    ((null loci) 'stale)
                    ;; Off either end is not an error the user caused: the
                    ;; chrome only offers the in-range direction, so this
                    ;; means the set changed under them.
                    ((or (< target 0) (>= target (length loci))) 'stale)
                    ((jetpacs-results--goto-buffer buf loci target) 'accepted)
                    (t 'rejected))))))
            ('file
             (let ((loci (plist-get nav :loci)))
               (cond
                ((null loci) 'stale)
                ((or (< target 0) (>= target (length loci))) 'stale)
                ((jetpacs-results--goto-file loci target) 'accepted)
                (t 'rejected))))
            (_ 'rejected)))))))

(defun jetpacs-results--nav-live-p (nav)
  "Non-nil when the stepper NAV can still step (its source survives)."
  (pcase (plist-get nav :kind)
    ('buffer (get-buffer (plist-get nav :buffer)))
    ('file (plist-get nav :loci))
    (_ nil)))

(defun jetpacs-results-buffer-view-actions (viewed-buffer-name)
  "Prev/next-match chrome for the region view, or nil.
Returns nodes when the stepper is armed, VIEWED-BUFFER-NAME is the
buffer the last visit landed in, and the set is still live; only the
in-range direction is offered at each end."
  (let ((nav jetpacs-results--nav))
    (when (and nav
               (equal viewed-buffer-name (plist-get nav :dest))
               (jetpacs-results--nav-live-p nav))
      (let* ((i (plist-get nav :index))
             (n (plist-get nav :count))
             (icons (jetpacs-node-advertised-p "icon_button"))
             (step (lambda (dir label desc)
                     (let ((action (jetpacs-action
                                    "results.step" :args (list :dir dir))))
                       (if icons
                           (jetpacs-icon-button
                            (if (< dir 0) "chevron_left" "chevron_right")
                            action :content-description desc)
                         (jetpacs-button label action))))))
        (let ((buttons
               (delq nil
                     (list
                      (when (> i 0)
                        (funcall step -1 "Previous"
                                 (format "Previous match (%d of %d)" i n)))
                      (when (< (1+ i) n)
                        (funcall step 1 "Next"
                                 (format "Next match (%d of %d)" (+ i 2) n)))))))
          (when buttons (list (apply #'jetpacs-row buttons))))))))

(provide 'jetpacs-results)
;;; jetpacs-results.el ends here
