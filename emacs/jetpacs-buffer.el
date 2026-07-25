;;; jetpacs-buffer.el --- Generic buffer renderer (Tier 0) -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Tier 0 of Jetpacs: render ANY Emacs buffer faithfully from its text plus
;; its text/overlay properties (face, display, invisible, keymap, button,
;; mouse-face), with interactive regions made tappable.  This is the
;; universal substrate — every major mode renders through here for free, no
;; per-package translator required.  Per-mode "skins" (Tier 1) are opt-in
;; overrides registered in `jetpacs-render-buffer-functions'.
;;
;; Emacs stays the single source of truth for styling: this module resolves
;; faces to span attributes and ships them; the device only paints the
;; spans (it never re-fontifies).
;;
;; Rung JC-1 of docs/PLAN-jetpacs-consumers.md, ported from poc-v1 with the
;; format-6 span drift applied (`:bold t' -> `:font-weight "bold"'; `:code'
;; folded into `:mono'; `:strike' and `baseline' dropped — format 6 has
;; neither) and two structural changes:
;;
;; - Emission is bounded by the LIVE welcome budgets, not just the line
;;   cap (plan section 2.5-5): `max_rich_spans' is spent down as the
;;   SPEC 4.5 AGGREGATE across the whole SurfaceSpec (not a per-node
;;   cap, which would sail past it), and the render stops before the
;;   node total would crowd `max_frame_bytes'.
;; - Decision D2: the two tap actions validate and return a status
;;   immediately, then run the buffer effect (which may prompt on the
;;   desktop, e.g. a widget field edit) from a `run-at-time' 0
;;   continuation — never inside the jsonrpc dispatch extent.
;;
;; The only seam back to the host is `jetpacs-buffer-refresh-function',
;; called with the originating surface id (or nil) after a tap's effect
;; runs; `jetpacs-shell' points it at `jetpacs-shell-push'.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'button)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)   ; jetpacs-defaction / jetpacs-client

;; --- Configuration ----------------------------------------------------------

(defcustom jetpacs-buffer-max-lines 500
  "Maximum number of lines the generic renderer emits for a buffer.
Buffers longer than this are truncated (with a trailing note) so a huge
magit/log/compilation buffer can't produce an unbounded surface.  The
welcome `max_rich_spans'/`max_frame_bytes' budgets bound emission
further when a client is attached."
  :type 'integer :group 'jetpacs)

(defcustom jetpacs-buffer-monospace t
  "When non-nil, the generic renderer paints buffer text monospace.
Most Emacs buffers (dired, magit, tables, source) rely on column
alignment, so monospace is the faithful default."
  :type 'boolean :group 'jetpacs)

(defcustom jetpacs-buffer-emit-colors t
  "When non-nil, carry a face's foreground color into the rendered span.
Only colors that differ from the default face are emitted, so semantic
color (diff add/remove, font-lock keywords, warnings) survives while
ordinary body text still uses the device theme's on-surface color."
  :type 'boolean :group 'jetpacs)

(defcustom jetpacs-line-numbers nil
  "Line numbers in the generic buffer view.
nil shows none; `absolute' shows buffer line numbers; `relative' shows
distances from point (the current line shows its absolute number,
vim's hybrid style)."
  :type '(choice (const :tag "Off" nil)
                 (const :tag "Absolute" absolute)
                 (const :tag "Relative" relative))
  :group 'jetpacs)

(defconst jetpacs-buffer--line-number-color "#8A8A8A"
  "Dim gray for line-number spans; legible on light and dark themes.")

(defconst jetpacs-buffer--frame-headroom 2048
  "Octets reserved from `max_frame_bytes' for the envelope and siblings.")

(defvar jetpacs-buffer-refresh-function nil
  "Function called with the originating surface id (or nil) after a tap.
`jetpacs-shell' sets this to `jetpacs-shell-push'; kept as a seam so
this module never depends on a specific UI layer.")

(defvar jetpacs-buffer-span-action-function nil
  "When non-nil, a function (POS BUFFER-NAME) -> ActionDescriptor or nil.
Consulted at the start of every span run before the generic actionable
check; a non-nil result becomes that run's tap action instead of the
default `emacs.buffer.act' dispatch.  Tier-1 skins let-bind this around
delegated region renders.  A signaling function counts as nil — a broken
skin routing must not cost the render.")

(defvar jetpacs-buffer--default-fg-hex nil
  "Hex of the default face foreground, bound for the duration of a render.")

(defvar jetpacs-buffer--default-bg-hex nil
  "Hex of the default face background, bound for the duration of a render.")

;; --- Face resolution --------------------------------------------------------

(defun jetpacs-buffer--color-hex (color)
  "Return COLOR (a name or hex string) as \"#RRGGBB\", or nil.
A literal #rrggbb/#rgb parses directly: `color-values' consults the
display's color table, and a tty or batch session snaps hex to the
nearest terminal color — wrong on the wire, where §16.6 hex is exact."
  (when (and (stringp color) (not (string-empty-p color)))
    (cond
     ((string-match-p "\\`#[0-9a-fA-F]\\{6\\}\\'" color) (upcase color))
     ((string-match-p "\\`#[0-9a-fA-F]\\{3\\}\\'" color)
      (upcase (apply #'string ?#
                     (cl-loop for i from 1 to 3
                              append (list (aref color i) (aref color i))))))
     (t (when-let* ((vals (ignore-errors (color-values color))))
          (apply #'format "#%02X%02X%02X"
                 (mapcar (lambda (v) (/ v 256)) vals)))))))

(defun jetpacs-buffer--face-refs (face)
  "Normalize a FACE property value into an ordered list of face refs.
Each ref is a face symbol or an attribute plist; earlier refs take
precedence, matching Emacs's left-to-right face merging."
  (cond
   ((null face) nil)
   ((symbolp face) (list face))
   ((and (consp face) (keywordp (car face))) (list face)) ; a single plist
   ((consp face)
    (let (refs)
      (dolist (f face)
        (setq refs (append refs (jetpacs-buffer--face-refs f))))
      refs))
   (t nil)))

(defun jetpacs-buffer--ref-attr (ref attr)
  "Read ATTR from a single face REF (symbol or plist); nil if unspecified.
An anonymous plist that lacks ATTR but names an `:inherit' face resolves
ATTR through the inherited face(s), matching Emacs's own merging."
  (let ((v (cond
            ((symbolp ref) (face-attribute ref attr nil t))
            ((listp ref)
             (if (plist-member ref attr)
                 (plist-get ref attr)
               (let ((inherit (plist-get ref :inherit)))
                 (and inherit
                      (jetpacs-buffer--attr
                       (jetpacs-buffer--face-refs inherit) attr)))))
            (t nil))))
    (if (eq v 'unspecified) nil v)))

(defun jetpacs-buffer--attr (refs attr)
  "First specified value of ATTR across REFS, in priority order."
  (cl-some (lambda (r) (jetpacs-buffer--ref-attr r attr)) refs))

(defconst jetpacs-buffer--bold-weights
  '(bold semi-bold semibold extra-bold extrabold ultra-bold ultrabold
    heavy black)
  "Weight symbols treated as bold.")

(defcustom jetpacs-buffer-code-faces
  '(org-verbatim org-code markdown-inline-code-face markdown-code-face)
  "Faces whose runs render monospace even when the buffer default is not.
Face attributes carry no \"this is code\" bit, so inline-code faces are
named here explicitly.  Format 6 has no separate `code' span chrome; the
faithful mapping is `:mono'."
  :type '(repeat face) :group 'jetpacs)

(defun jetpacs-buffer--span-style (face)
  "Return a span-style plist for FACE, or nil for an unstyled run.
Format-6 members only: `:font-weight' \"bold\", `:italic', `:underline',
`:mono' (inline-code faces), `:color', `:bg'.  COLOR/:bg are included
only when they resolve and differ from the render's default
foreground/background, so ordinary text carries neither."
  (condition-case nil
      (let* ((refs (jetpacs-buffer--face-refs face))
             (weight (jetpacs-buffer--attr refs :weight))
             (slant (jetpacs-buffer--attr refs :slant))
             (underline (jetpacs-buffer--attr refs :underline))
             (fg (and jetpacs-buffer-emit-colors
                      (jetpacs-buffer--attr refs :foreground)))
             (hex (and fg (jetpacs-buffer--color-hex fg)))
             (bg (and jetpacs-buffer-emit-colors
                      (jetpacs-buffer--attr refs :background)))
             (bghex (and bg (jetpacs-buffer--color-hex bg))))
        (append
         (when (memq weight jetpacs-buffer--bold-weights)
           '(:font-weight "bold"))
         (when (memq slant '(italic oblique)) '(:italic t))
         (when underline '(:underline t))
         (when (cl-some (lambda (r)
                          (and (symbolp r)
                               (memq r jetpacs-buffer-code-faces)))
                        refs)
           '(:mono t))
         (when (and hex (not (equal hex jetpacs-buffer--default-fg-hex)))
           (list :color hex))
         (when (and bghex (not (equal bghex jetpacs-buffer--default-bg-hex)))
           (list :bg bghex))))
    (error nil)))

;; --- Interactivity ----------------------------------------------------------

(defun jetpacs-buffer--widget-p (obj)
  "Non-nil if OBJ is a widget.el widget object.
Own predicate (rather than `widgetp') so detection needs no wid-edit;
when a buffer actually contains widgets, wid-edit is already loaded."
  (and (consp obj) (symbolp (car obj)) (get (car obj) 'widget-type)))

(defun jetpacs-buffer--widget-at (pos)
  "The widget.el widget at POS as (button . W) or (field . W), else nil."
  (let ((b (get-char-property pos 'button)))
    (if (jetpacs-buffer--widget-p b)
        (cons 'button b)
      (let ((f (get-char-property pos 'field)))
        (and (jetpacs-buffer--widget-p f) (cons 'field f))))))

(defun jetpacs-buffer--actionable-p (pos)
  "Non-nil if the char at POS belongs to a tappable region.
True for text/widget buttons, widget editable fields, regions carrying a
`mouse-face', and regions with their own `keymap'/`local-map' (magit
sections, info refs, ...).  The major-mode keymap is buffer-local, not a
text property, so this never marks the whole buffer tappable."
  (or (get-char-property pos 'button)
      (jetpacs-buffer--widget-p (get-char-property pos 'field))
      (get-char-property pos 'mouse-face)
      (keymapp (get-char-property pos 'keymap))
      (keymapp (get-char-property pos 'local-map))))

;; --- The exposure table (SPEC 23.1 argument validation) --------------------
;;
;; A tap descriptor names a buffer and an offset, and both come back over
;; the wire.  23.1 puts that data outside the trust boundary: "Emacs MUST
;; validate action arguments ... before use."  Without a record of what was
;; actually rendered, `emacs.buffer.act' would run whatever command lives
;; at any offset of any live buffer — reaching Customize's [Apply and Save],
;; a package-menu install button, or an eww link in a buffer the user never
;; put on the phone.  So every emitted (BUFFER . POS) is recorded, and a tap
;; is honored only if it was genuinely offered.

(defvar jetpacs-buffer--exposed (make-hash-table :test #'equal)
  "Map of BUFFER-NAME -> hash of exposed POS -> t, for the live render.
Rebuilt per `jetpacs-buffer--render-region'; a tap for an unrecorded
\(buffer, pos) is refused.")

(defun jetpacs-buffer--expose (buffer-name pos)
  "Record that POS in BUFFER-NAME was emitted as a tap target."
  (let ((tbl (or (gethash buffer-name jetpacs-buffer--exposed)
                 (puthash buffer-name (make-hash-table :test #'eql)
                          jetpacs-buffer--exposed))))
    (puthash pos t tbl)))

(defun jetpacs-buffer-exposed-p (buffer-name pos)
  "Non-nil when POS in BUFFER-NAME was emitted by the last render."
  (when-let* ((tbl (gethash buffer-name jetpacs-buffer--exposed)))
    (gethash pos tbl)))

(defun jetpacs-buffer-forget-exposed (&optional buffer-name)
  "Drop the exposure record for BUFFER-NAME, or all of it."
  (if buffer-name
      (remhash buffer-name jetpacs-buffer--exposed)
    (clrhash jetpacs-buffer--exposed)))

(defun jetpacs-buffer--span-action (pos buffer-name)
  "The tap ActionDescriptor for the run starting at POS, or nil.
The skin override wins; otherwise an actionable region gets the generic
`emacs.buffer.act' dispatch (format-6 plist args)."
  (or (and jetpacs-buffer-span-action-function
           (condition-case nil
               (funcall jetpacs-buffer-span-action-function pos buffer-name)
             (error nil)))
      (when (jetpacs-buffer--actionable-p pos)
        (jetpacs-buffer--expose buffer-name pos)
        (jetpacs-action "emacs.buffer.act"
                        :args (list :buffer buffer-name :pos pos)))))

;; --- Folding ----------------------------------------------------------------
;;
;; Universal fold/unfold without any per-mode renderer.  A line is
;; "expandable" when the text right after it is currently invisible (how
;; magit/org/outline/hideshow all hide a collapsed body); the action runs
;; whatever fold command the buffer itself binds, gated by an allowlist.

(defcustom jetpacs-buffer-fold-commands
  '(magit-section-toggle magit-section-cycle magit-section-cycle-global
    org-cycle org-fold-show-entry org-fold-hide-subtree
    outline-toggle-children outline-cycle outline-show-subtree
    outline-hide-subtree hs-toggle-hiding)
  "Commands treated as safe fold toggles for the generic fold affordance.
Only a command in this list will be invoked by `jetpacs.buffer.fold', so
the phone can never trigger an arbitrary command through the fold path."
  :type '(repeat function) :group 'jetpacs)

(defun jetpacs-buffer--invisible-at (pos)
  "Non-nil if the char at POS is currently folded away (invisible)."
  (let ((v (get-char-property pos 'invisible)))
    (and v (invisible-p v))))

(defun jetpacs-buffer--hidden-follows-p (eol limit)
  "Non-nil if a folded (invisible) region begins right after EOL.
Bounded by LIMIT.  Checks the end-of-line chars and the start of the
next line, since modes differ on which carries `invisible'."
  (or (and (< eol limit) (jetpacs-buffer--invisible-at eol))
      (and (< (1+ eol) limit) (jetpacs-buffer--invisible-at (1+ eol)))
      (save-excursion
        (goto-char (min eol (max (point-min) (1- limit))))
        (forward-line 1)
        (and (< (point) limit) (jetpacs-buffer--invisible-at (point))))))

(defun jetpacs-buffer--fold-span (pos buffer-name text)
  "A tappable affordance span toggling the fold at heading position POS."
  (jetpacs-buffer--expose buffer-name pos)
  (jetpacs-span text
                :on-tap (jetpacs-action
                         "jetpacs.buffer.fold"
                         :args (list :buffer buffer-name :pos pos))))

;; --- Region -> spans --------------------------------------------------------

(defun jetpacs-buffer--scalar-text (s)
  "S with every non-scalar char replaced by U+FFFD (SPEC 4.1).
Emacs stores an undecodable octet as a raw-byte char in
#x3FFF80..#x3FFFFF, and a lone surrogate as #xD800..#xDFFF; neither is a
Unicode scalar value, and `json-serialize' signals `wrong-type-argument'
on both.  Any buffer that is not valid UTF-8 — a latin-1 source, a
binary, a truncated log, a mid-stream broken sequence in
*compilation* — would otherwise take down the whole render."
  (if (string-match-p "[\x3FFF80-\x3FFFFF\xD800-\xDFFF]" s)
      (replace-regexp-in-string "[\x3FFF80-\x3FFFFF\xD800-\xDFFF]" "�"
                                s t t)
    s))

(defun jetpacs-buffer--expand-tabs (text col)
  "Expand TABs in TEXT to spaces given the starting column COL.
Returns (EXPANDED-TEXT . END-COL).  Text with no TAB is returned as-is,
so the common line pays only a `string-search'."
  (if (not (string-search "\t" text))
      (cons text (+ col (length text)))
    (let ((c col) parts)
      (dolist (ch (append text nil))
        (if (eq ch ?\t)
            (let ((n (- tab-width (mod c tab-width))))
              (push (make-string n ?\s) parts)
              (setq c (+ c n)))
          (push (char-to-string ch) parts)
          (setq c (1+ c))))
      (cons (apply #'concat (nreverse parts)) c))))

(defun jetpacs-buffer--offscreen-display-p (disp)
  "Non-nil when display spec DISP renders outside the text area.
Fringe bitmaps and margin specs show in the fringe/margin, never in the
text flow — the text they cover is a placeholder that must not render."
  (and (consp disp)
       (or (memq (car-safe disp) '(left-fringe right-fringe))
           (eq (car-safe (car-safe disp)) 'margin)
           (and (consp (car-safe disp))
                (cl-some #'jetpacs-buffer--offscreen-display-p disp)))))

(defun jetpacs-buffer--space-width (disp col)
  "Columns a `(space ...)' display spec DISP occupies starting at COL."
  (let ((plist (cdr disp)))
    (cond
     ((plist-member plist :width)
      (let ((w (plist-get plist :width)))
        (max 0 (if (numberp w) (round w) 1))))
     ((plist-member plist :align-to)
      (let ((to (plist-get plist :align-to)))
        (max 1 (- (if (numberp to) (round to) col) col))))
     (t 1))))

(defun jetpacs-buffer--string-spans (str col)
  "Render a propertized STR (an overlay before/after-string) into spans.
Returns (SPANS . END-COL); honors `face'/`font-lock-face', string
`display' overrides, and TAB expansion.  Runs covered by an offscreen
display spec render nothing."
  (let ((i 0) (n (length str)) (c col) out)
    (while (< i n)
      (let* ((next (or (next-property-change i str) n))
             (disp (get-text-property i 'display str))
             (raw (cond
                   ((stringp disp) disp)
                   ((jetpacs-buffer--offscreen-display-p disp) nil)
                   ((and (consp disp) (eq (car disp) 'space))
                    (make-string (jetpacs-buffer--space-width disp c) ?\s))
                   (t (substring-no-properties str i next))))
             (raw (and raw (jetpacs-buffer--scalar-text raw)))
             (face (or (get-text-property i 'face str)
                       (get-text-property i 'font-lock-face str)))
             (style (jetpacs-buffer--span-style face)))
        (when raw
          (let ((exp (jetpacs-buffer--expand-tabs raw c)))
            (setq c (cdr exp))
            (unless (string-empty-p (car exp))
              (push (apply #'jetpacs-span (car exp)
                           (append style
                                   (when jetpacs-buffer-monospace
                                     '(:mono t))))
                    out))))
        (setq i next)))
    (cons (nreverse out) c)))

(defun jetpacs-buffer--overlay-strings (bol eol)
  "Insertions ((POS TIE STRING) ...) from overlay strings on a line.
`before-string' is placed at the overlay start, `after-string' at its
end, when those fall within [BOL, EOL].  Invisible overlays contribute
nothing.  These are OVERLAY properties, not char properties, so the main
span walk never sees them — this surfaces flymake inline hints, diff-hl
markers, and similar virtual text."
  (let (ins)
    (dolist (ov (overlays-in bol (min (1+ eol) (point-max))))
      (let ((iv (overlay-get ov 'invisible)))
        (unless (and iv (invisible-p iv))
          (let ((bs (overlay-get ov 'before-string))
                (as (overlay-get ov 'after-string))
                (os (overlay-start ov))
                (oe (overlay-end ov)))
            (when (and (stringp bs) (>= os bol) (<= os eol))
              (push (list os 0 bs) ins))
            (when (and (stringp as) (>= oe bol) (<= oe eol))
              (push (list oe 1 as) ins))))))
    (sort ins (lambda (a b) (or (< (car a) (car b))
                                (and (= (car a) (car b))
                                     (< (nth 1 a) (nth 1 b))))))))

(defun jetpacs-buffer--line-spans (bol eol buffer-name)
  "Build the list of spans for the buffer text in [BOL, EOL).
Honors `invisible' (skips folded text), string and `(space ...)'
`display' overrides, and overlay before/after-strings; expands TABs;
maps `face'/`font-lock-face' to styling; and attaches a tap action at
the start of each actionable property run."
  (let ((pos bol) (col 0) spans
        (inserts (jetpacs-buffer--overlay-strings bol eol)))
    (cl-flet ((flush (upto)
                (while (and inserts (<= (caar inserts) upto))
                  (let ((ss (jetpacs-buffer--string-spans
                             (nth 2 (pop inserts)) col)))
                    (setq spans (nconc (nreverse (car ss)) spans)
                          col (cdr ss))))))
      (while (< pos eol)
        (flush pos)
        (let ((next (next-char-property-change pos eol)))
          (when (<= next pos) (setq next (1+ pos))) ; defensive: always advance
          (setq next (min next eol))
          (let ((invis (get-char-property pos 'invisible)))
            (unless (and invis (invisible-p invis))
              (let* ((disp (get-char-property pos 'display))
                     (face (or (get-char-property pos 'face)
                               (get-char-property pos 'font-lock-face)))
                     (style (jetpacs-buffer--span-style face))
                     (act (jetpacs-buffer--span-action pos buffer-name))
                     text)
                (cond
                 ((stringp disp)
                  (setq text disp col (+ col (length disp))))
                 ((jetpacs-buffer--offscreen-display-p disp)
                  (setq text nil))
                 ((and (consp disp) (eq (car disp) 'space))
                  (let ((w (jetpacs-buffer--space-width disp col)))
                    (setq text (make-string w ?\s) col (+ col w))))
                 (t
                  (let ((exp (jetpacs-buffer--expand-tabs
                              (jetpacs-buffer--scalar-text
                               (buffer-substring-no-properties pos next))
                              col)))
                    (setq text (car exp) col (cdr exp)))))
                (when (and (stringp text) (not (string-empty-p text)))
                  (push (apply #'jetpacs-span text
                               (append style
                                       (when jetpacs-buffer-monospace
                                         '(:mono t))
                                       (when act (list :on-tap act))))
                        spans)))))
          (setq pos next)))
      (flush eol))
    (nreverse spans)))

(defun jetpacs-buffer--fold-state (bol eol limit)
  "Return `folded', `unfolded', or nil if not a foldable heading."
  (let ((magit-sec (get-char-property bol 'magit-section)))
    (cond
     (magit-sec
      (if (and (fboundp 'magit-section-hidden)
               (magit-section-hidden magit-sec))
          'folded
        'unfolded))
     ((and (bound-and-true-p outline-regexp)
           (save-excursion
             (goto-char bol)
             (looking-at outline-regexp)))
      (if (jetpacs-buffer--hidden-follows-p eol limit)
          'folded
        'unfolded))
     (t nil))))

(defun jetpacs-buffer--line-number-span (ln pt-line fmt)
  "A dim gutter span for line LN; PT-LINE is point's line, FMT the format.
With `jetpacs-line-numbers' `relative', shows the distance from point —
except on point's own line, which shows its absolute number undimmed."
  (let ((current (and pt-line (= ln pt-line))))
    (jetpacs-span (format fmt (if (and (eq jetpacs-line-numbers 'relative)
                                       (not current))
                                  (abs (- ln pt-line))
                                ln))
                  :mono t
                  :color (unless current jetpacs-buffer--line-number-color))))

;; --- Budgets (plan section 2.5-5) -------------------------------------------

(defvar jetpacs-buffer--budget nil
  "When non-nil, a cons (SPANS-LEFT . BYTES-LEFT) shared across renders.
SPEC 4.5's counts are aggregates across ONE SurfaceSpec, but each
`jetpacs-buffer--render-region' call otherwise starts from the full
limit — so a spec containing two rendered regions, or a spec plus its
`stale_spec', would each take a whole allowance and together blow the
budget.  Bind with `jetpacs-buffer-with-budget' around a build.")

(defmacro jetpacs-buffer-with-budget (&rest body)
  "Run BODY sharing ONE SPEC 4.5 render budget across every region."
  (declare (indent 0))
  `(let ((jetpacs-buffer--budget (jetpacs-buffer--budgets)))
     ,@body))

(defun jetpacs-buffer--budgets ()
  "The live welcome budgets as (MAX-SPANS . MAX-BYTES), members nil-able.
MAX-SPANS is `max_rich_spans', which SPEC 4.5 defines as an AGGREGATE
count across one SurfaceSpec — not a per-node cap — so the walk spends
it down across every line.  MAX-BYTES is the whole-surface byte budget
derived from `max_frame_bytes' minus `jetpacs-buffer--frame-headroom'.
Both nil when no client is attached (offline renders and tests are
bound only by the line cap)."
  (if-let* ((client (jetpacs-client))
            (limits (ebp-client-limits client)))
      (cons (plist-get limits :max_rich_spans)
            (when-let* ((frame (plist-get limits :max_frame_bytes)))
              (max 1024 (- frame jetpacs-buffer--frame-headroom))))
    (cons nil nil)))

(defun jetpacs-buffer--cap-spans (spans max-spans)
  "SPANS truncated to exactly MAX-SPANS members, an ellipsis marking the cut.
The result never exceeds MAX-SPANS: the ellipsis replaces the last kept
span rather than being appended past the budget."
  (cond
   ((or (null max-spans) (<= (length spans) max-spans)) spans)
   ((<= max-spans 1) (list (jetpacs-span "…")))
   (t (append (seq-take spans (1- max-spans)) (list (jetpacs-span "…"))))))

(defun jetpacs-buffer--node-bytes (node)
  "The canonical serialized size of NODE in octets."
  (string-bytes (jetpacs-node->canonical-json node)))

(defun jetpacs-buffer--rich-text-advertised-p ()
  "Non-nil when the live `app' profile advertises `rich_text' (SPEC 16.2).
`rich_text' is OPTIONAL — the Core Node Set is only `text', `row',
`column', `box', `spacer', `divider', `button', `text_input' — so a
Companion need not support it, and SPEC 16.2 forbids Emacs emitting an
unadvertised type.  With no client attached (offline renders, tests)
assume the richer form."
  (if-let* ((client (jetpacs-client))
            (profile (plist-get (ebp-client-profiles client) :app)))
      (and (member "rich_text" (append (plist-get profile :node_types) nil))
           t)
    t))

(defun jetpacs-buffer--spans->text (spans)
  "Flatten SPANS into one Core `text' node — the non-`rich_text' fallback.
Per-span styling and tap actions cannot survive: SPEC 17.2's `text' node
carries neither.  The content does, which beats the alternative — the
16.2 sender gate refusing the entire buffer surface."
  (jetpacs-text (mapconcat (lambda (s) (or (plist-get s :text) "")) spans "")
                :style (if jetpacs-buffer-monospace "mono" "body")))

;; --- Region -> nodes --------------------------------------------------------

(defun jetpacs-buffer--render-region (beg end buffer-name &optional mark-pos)
  "Return a list of `rich_text' nodes for [BEG, END) of the current buffer.
One node per line; blank lines keep their vertical space.  Bounded by
`jetpacs-buffer-max-lines', by the SPEC 4.5 aggregate `max_rich_spans'
across the whole spec, and by the frame byte budget — exceeding any of
them stops the walk and appends a visible note rather than over-emitting
(plan 2.5-5; 4.5 \"A sender MUST respect reported limits and MUST NOT
rely on receiver truncation\").  MARK-POS, when non-nil, flags the line
containing that position as the scroll target (`:scroll_here')."
  (let* ((jetpacs-buffer--default-fg-hex
          (jetpacs-buffer--color-hex
           (face-attribute 'default :foreground nil t)))
         (jetpacs-buffer--default-bg-hex
          (jetpacs-buffer--color-hex
           (face-attribute 'default :background nil t)))
         ;; A shared budget (see `jetpacs-buffer-with-budget') carries
         ;; across regions; otherwise this render gets its own allowance.
         (budgets (or jetpacs-buffer--budget (jetpacs-buffer--budgets)))
         (spans-left (car budgets))     ; SPEC 4.5: aggregate, spent down
         (bytes-left (cdr budgets))
         (exhausted nil)
         (rich-ok (jetpacs-buffer--rich-text-advertised-p))
         (pt-line (and jetpacs-line-numbers (line-number-at-pos (point))))
         (num-fmt (and jetpacs-line-numbers
                       (format "%%%dd " (length (number-to-string
                                                 (line-number-at-pos end))))))
         (ln (and jetpacs-line-numbers (line-number-at-pos beg)))
         (count 0)
         (truncated nil)
         nodes)
    ;; This render supersedes the last one for this buffer: only offsets
    ;; emitted below stay tappable (SPEC 23.1).
    (jetpacs-buffer-forget-exposed buffer-name)
    (ignore-errors (font-lock-ensure beg end))
    (save-excursion
      (goto-char beg)
      (cl-block walk
        (while (and (< (point) end) (< count jetpacs-buffer-max-lines))
          (let* ((bol (line-beginning-position))
                 (eol (min end (line-end-position)))
                 (node nil))
            (cond
             ;; A page break (^L alone on the line) renders as a divider.
             ((and (< bol eol)
                   (save-excursion (goto-char bol) (looking-at "\f+$")))
              (setq node (jetpacs-divider)))
             (t
              (let ((spans (jetpacs-buffer--line-spans bol eol buffer-name)))
                ;; A fully-folded line (no visible spans, hidden at bol) is
                ;; dropped entirely so collapsed content truly disappears.
                ;; A collapsed heading gets a trailing expand affordance.
                (unless (and (null spans)
                             (jetpacs-buffer--invisible-at bol))
                  (pcase (jetpacs-buffer--fold-state bol eol end)
                    ('folded
                     (setq spans
                           (append (or spans (list (jetpacs-span " ")))
                                   (list (jetpacs-buffer--fold-span
                                          bol buffer-name "  ▸")))))
                    ('unfolded
                     (setq spans
                           (append (or spans (list (jetpacs-span " ")))
                                   (list (jetpacs-buffer--fold-span
                                          bol buffer-name "  ▾"))))))
                  (setq spans (or spans (list (jetpacs-span " "))))
                  ;; `line-prefix' (org-indent's virtual indentation) is a
                  ;; text property, not buffer text — prepend it dimmed.
                  (let ((prefix (get-char-property bol 'line-prefix)))
                    (when (stringp prefix)
                      (setq spans
                            (cons (jetpacs-span
                                   prefix :mono t
                                   :color jetpacs-buffer--line-number-color)
                                  spans))))
                  (when ln
                    (setq spans (cons (jetpacs-buffer--line-number-span
                                       ln pt-line num-fmt)
                                      spans)))
                  ;; SPEC 4.5: `max_rich_spans' is an AGGREGATE count
                  ;; across one SurfaceSpec, so spend it down across
                  ;; lines — a per-line cap would sail past it.
                  (when spans-left
                    (when (> (length spans) spans-left)
                      (setq spans (jetpacs-buffer--cap-spans spans spans-left)
                            exhausted t))
                    (setq spans-left (- spans-left (length spans))))
                  (let ((line (if rich-ok
                                  (jetpacs-rich-text spans)
                                (jetpacs-buffer--spans->text spans))))
                    (setq node
                          (if (and mark-pos (>= mark-pos bol)
                                   (<= mark-pos eol))
                              (jetpacs-with-attrs line :scroll_here t)
                            line)))))))
            (when node
              ;; The byte budget stops the walk BEFORE over-emitting.
              (when bytes-left
                (let ((size (jetpacs-buffer--node-bytes node)))
                  (when (> size bytes-left)
                    (setq truncated t)
                    (cl-return-from walk))
                  (setq bytes-left (- bytes-left size))))
              (push node nodes)
              (setq count (1+ count))
              ;; The aggregate span budget is spent: stop here.
              (when (or exhausted (and spans-left (<= spans-left 0)))
                (setq truncated t)
                (cl-return-from walk))))
          (when ln (setq ln (1+ ln)))
          (forward-line 1))))
    ;; Hand what is left back to a shared budget, so the next region in
    ;; this spec starts where this one stopped.
    (when jetpacs-buffer--budget
      (setcar jetpacs-buffer--budget spans-left)
      (setcdr jetpacs-buffer--budget bytes-left))
    (when truncated
      (push (jetpacs-text "… output truncated (surface budget)"
                          :style "caption")
            nodes))
    (nreverse nodes)))

;; --- Public: generic renderer + dispatch registry ---------------------------

(defun jetpacs-buffer-render (&optional buffer)
  "Render BUFFER (default current) generically into a list of nodes.
Truncated to `jetpacs-buffer-max-lines'; a caption note is appended if
cut."
  (let ((buf (get-buffer (or buffer (current-buffer)))))
    (unless buf (error "No such buffer: %s" buffer))
    (with-current-buffer buf
      (let* ((name (buffer-name buf))
             (total (count-lines (point-min) (point-max)))
             (nodes (jetpacs-buffer--render-region
                     (point-min) (point-max) name)))
        (if (> total jetpacs-buffer-max-lines)
            (append nodes
                    (list (jetpacs-text
                           (format "… %d more line(s) (showing first %d)"
                                   (- total jetpacs-buffer-max-lines)
                                   jetpacs-buffer-max-lines)
                           :style "caption")))
          nodes)))))

(defun jetpacs-buffer-render-region (buffer beg end &optional mark-pos)
  "Render [BEG, END) of BUFFER generically into a list of nodes.
BEG and END are clamped to the buffer; the caps still apply.  MARK-POS,
when non-nil, flags its line as the scroll target."
  (let ((buf (get-buffer buffer)))
    (unless buf (error "No such buffer: %s" buffer))
    (with-current-buffer buf
      (let* ((beg (max (point-min) (min (or beg (point-min)) (point-max))))
             (end (max beg (min (or end (point-max)) (point-max)))))
        (jetpacs-buffer--render-region beg end (buffer-name buf) mark-pos)))))

(defun jetpacs-buffer-render-tail (buffer lines)
  "Render the last LINES lines of BUFFER into a list of nodes.
For transcript-shaped buffers (comint REPLs, logs) the interesting end
is the bottom.  A leading caption marks elided output."
  (let ((buf (get-buffer buffer)))
    (unless buf (error "No such buffer: %s" buffer))
    (with-current-buffer buf
      (let ((beg (save-excursion
                   (goto-char (point-max))
                   (forward-line (- (max 1 lines)))
                   (point))))
        (append
         (when (> beg (point-min))
           (list (jetpacs-text (format "… %d earlier line(s) not shown"
                                       (count-lines (point-min) beg))
                               :style "caption")))
         (jetpacs-buffer--render-region beg (point-max)
                                        (buffer-name buf)))))))

(defvar jetpacs-render-buffer-functions nil
  "Alist of (MAJOR-MODE . FUNCTION) Tier-1 renderer skins.
FUNCTION takes the buffer and returns a list of nodes.  A mode with no
entry falls through to the generic `jetpacs-buffer-render'.  Derived
modes match their nearest registered ancestor; first match wins.")

(defun jetpacs-render-buffer-register (mode fn)
  "Register FN as the Tier-1 renderer skin for MODE."
  (setf (alist-get mode jetpacs-render-buffer-functions) fn))

(defun jetpacs-render-buffer (&optional buffer)
  "Render BUFFER via its registered skin, else the generic renderer.
The single dispatch seam: Tier 1 is purely additive on Tier 0."
  (let ((buf (get-buffer (or buffer (current-buffer)))))
    (with-current-buffer buf
      (let ((fn (seq-some (lambda (cell)
                            (and (derived-mode-p (car cell)) (cdr cell)))
                          jetpacs-render-buffer-functions)))
        (if fn (funcall fn buf) (jetpacs-buffer-render buf))))))

;; --- Tap dispatch ------------------------------------------------------------

(declare-function widget-apply-action "wid-edit" (widget &optional event))
(declare-function widget-field-value-get "wid-edit" (widget &optional no-truncate))
(declare-function widget-field-value-set "wid-edit" (widget value))

(defun jetpacs-buffer--widget-invoke (hit)
  "Activate widget HIT, a (button . W) or (field . W) pair.
Buttons run their :action.  A field tap edits the field's raw text
through a desktop `read-string' prompt — this runs from the tap's
`run-at-time' continuation (decision D2), never inside the jsonrpc
dispatch extent.  A JC-4 dialog bridge will re-route it to the phone."
  (pcase hit
    (`(button . ,w) (widget-apply-action w) t)
    (`(field . ,_w)
     ;; Editing a field needs a value from the user, and the effect now
     ;; runs INSIDE the jsonrpc dispatch extent (see
     ;; `jetpacs-buffer--defer-refresh'), where a `read-string' would
     ;; wedge the connection — on a headless daemon, permanently.  Until
     ;; the JC-4 dialog bridge can carry the prompt to the phone, a field
     ;; tap is refused rather than answered with a lie or a hang.
     (error "jetpacs: editing a widget field needs the dialog bridge \
(JC-4); tap refused"))))

(defun jetpacs-buffer-call-shimmed (cmd &optional on-error)
  "Run command CMD with window-display and input-event shims.
Returns (BUF . POS): the buffer made current and point after CMD.
Buffer-display functions are neutered so nothing pops a desktop window;
the triggering input event is cleared so event-driven goto commands
navigate to point rather than a stale pending event; `this-command' and
`last-command' are pinned so repeat-style commands never extend stale
state.  Errors are swallowed — unless ON-ERROR is a function, called
with the error.  Call with the origin buffer current and point placed."
  (let (dest-buf dest-pos)
    (save-window-excursion
      (cl-letf (((symbol-function 'pop-to-buffer)
                 (lambda (b &rest _)
                   (set-buffer (get-buffer b)) (current-buffer)))
                ((symbol-function 'pop-to-buffer-same-window)
                 (lambda (b &rest _)
                   (set-buffer (get-buffer b)) (current-buffer)))
                ((symbol-function 'switch-to-buffer)
                 (lambda (b &rest _)
                   (set-buffer (get-buffer b)) (current-buffer)))
                ((symbol-function 'switch-to-buffer-other-window)
                 (lambda (b &rest _)
                   (set-buffer (get-buffer b)) (current-buffer))))
        (condition-case err
            (let ((last-input-event nil)
                  (last-nonmenu-event nil)
                  (this-command cmd)
                  (last-command 'jetpacs-buffer-call-shimmed))
              (call-interactively cmd))
          (error (when on-error (funcall on-error err)) nil))
        (setq dest-buf (current-buffer) dest-pos (point))))
    (cons dest-buf dest-pos)))

(defun jetpacs-buffer-invoke-at (buffer-name pos)
  "Run the tap action at POS in BUFFER-NAME; non-nil if one fired.
Tries, in order: activate a widget.el widget, push a button, then the
region keymap's binding for RET / mouse-2 / mouse-1.  Runs with the
buffer current and point at POS.  Runs from a tap continuation, outside
the jsonrpc dispatch extent (decision D2)."
  (let ((buf (get-buffer buffer-name)))
    (when (and buf (numberp pos))
      (with-current-buffer buf
        (goto-char (min (max (point-min) (truncate pos)) (point-max)))
        ;; Clear the triggering input event: link/visit commands reached
        ;; through the keymap branch read `last-input-event' and would
        ;; jump to a stale pending event instead of point.
        (let ((last-input-event nil)
              (last-nonmenu-event nil))
          (cond
           ;; widget.el first: widgets store the widget object in the
           ;; `button' property, which fools button.el's `button-at'.
           ((jetpacs-buffer--widget-at (point))
            (jetpacs-buffer--widget-invoke
             (jetpacs-buffer--widget-at (point))))
           ((button-at (point)) (push-button) t)
           (t
            (let* ((km (or (get-char-property (point) 'keymap)
                           (get-char-property (point) 'local-map)))
                   (cmd (and (keymapp km)
                             (or (lookup-key km (kbd "RET"))
                                 (lookup-key km [return])
                                 (lookup-key km [mouse-2])
                                 (lookup-key km [mouse-1])))))
              (when (commandp cmd)
                (call-interactively cmd)
                t)))))))))

(defun jetpacs-buffer--refresh (surface)
  "Re-push SURFACE through the host seam after a tap's effect ran."
  (when (functionp jetpacs-buffer-refresh-function)
    (condition-case err
        (funcall jetpacs-buffer-refresh-function surface)
      (error (message "jetpacs-buffer: refresh failed: %s"
                      (error-message-string err))))))

(defun jetpacs-buffer--defer-refresh (surface)
  "Re-push SURFACE from a zero-delay continuation.
Only the REFRESH is deferred.  The tap's effect itself must already
have run: SPEC 14.4 says \"Returning `accepted' merely because a
volatile callback was scheduled is not conforming\" — Emacs dying
before the timer fired would leave a committed receipt (so redelivery
answers `duplicate') and no effect, losing the user's intent silently.
Decision D2 bans blocking on the USER inside the dispatch extent, not
bounded local work, so the effect runs synchronously and only the push
— which needs the mutated buffer — is deferred."
  (run-at-time 0 nil (lambda () (jetpacs-buffer--refresh surface))))

;; --- The two Tier-0 actions (registered through the JC-0 shim) --------------

(defun jetpacs-buffer--tap-status (args params effect)
  "Validate a tap and run EFFECT, returning its SPEC 14.4 status.
Three gates, in the order 14.1/14.5/23.1 require:
- unresolvable arguments are permanently invalid -> `rejected' (14.1);
- an event created against a snapshot older than the surface's live
  floor named an offset that may since have moved -> `stale' (14.5),
  which the Companion may re-present, unlike terminal `rejected';
- an offset this Emacs never actually emitted as a tap target is
  outside the trust boundary -> `rejected' (23.1).
EFFECT runs synchronously so `accepted' names a completed effect (14.4);
a signalling effect reaches the JC-0 shim and answers `rejected'."
  (let ((buffer (plist-get args :buffer))
        (pos (plist-get args :pos)))
    (cond
     ((not (and (stringp buffer) (numberp pos) (get-buffer buffer)))
      'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-buffer-exposed-p buffer pos))
      (message "jetpacs-buffer: refused a tap at an offset never rendered")
      'rejected)
     (t
      (funcall effect buffer pos)
      (jetpacs-buffer--defer-refresh (plist-get params :surface))
      'accepted))))

(jetpacs-defaction "emacs.buffer.act"
  (lambda (args params)
    (jetpacs-buffer--tap-status args params #'jetpacs-buffer-invoke-at)))

(jetpacs-defaction "jetpacs.buffer.fold"
  (lambda (args params)
    (jetpacs-buffer--tap-status args params
                                #'jetpacs-buffer-toggle-fold-at)))

;; --- Fold dispatch ------------------------------------------------------------

(defun jetpacs-buffer--run-fold-toggle ()
  "Run the current buffer's own fold toggle at point; non-nil if one ran.
Prefer the command the buffer binds to TAB when it is a known fold
toggle; otherwise the first `jetpacs-buffer-fold-commands' member bound
in this buffer.  Never runs a command outside that allowlist."
  (let ((tab (or (key-binding (kbd "TAB")) (key-binding (kbd "<tab>")))))
    (cond
     ((and (commandp tab) (memq tab jetpacs-buffer-fold-commands))
      (call-interactively tab) t)
     (t
      (let ((cmd (cl-find-if
                  (lambda (c)
                    (and (commandp c)
                         (where-is-internal c (current-active-maps))))
                  jetpacs-buffer-fold-commands)))
        (when cmd (call-interactively cmd) t))))))

(defun jetpacs-buffer-toggle-fold-at (buffer-name pos)
  "Toggle the fold at POS in BUFFER-NAME using the buffer's own command.
Point is placed on the heading first, so the mode's toggle acts on the
right section.  Runs from a tap continuation (decision D2)."
  (let ((buf (get-buffer buffer-name)))
    (when (and buf (numberp pos))
      (with-current-buffer buf
        (goto-char (min (max (point-min) (truncate pos)) (point-max)))
        (jetpacs-buffer--run-fold-toggle)))))

(provide 'jetpacs-buffer)
;;; jetpacs-buffer.el ends here
