;;; jetpacs-org-render.el --- Org buffer render skin (JA-5) -*- lexical-binding: t; -*-

;;; Commentary:

;; The org analogue of the hypertext substrate: a Tier-1 skin registered
;; for org-mode buffers.  Deliberately flat and unopinionated — the body
;; IS the Tier-0 faithful line render (the user's font-lock faces, org's
;; own folding, tappable links, the caps), and only elements that have a
;; native SDUI node are upgraded in place:
;;
;;   -----                → a real divider
;;   | org | tables |     → the native table node (header rows, rules and
;;                          column alignment kept; table.el tables and
;;                          #+TBLFM stay text)
;;   [[file:img.png]]     → an image node for paragraphs that are exactly
;;                          one image link — local files ship as data:
;;                          URIs through the root allowlist, https URLs
;;                          pass through for the device to fetch
;;   \begin{…}…\end{…}    → (JA-5c) the formula through org's own LaTeX
;;                          toolchain, compiled off the dispatch extent
;;   #+CAPTION: …         → a caption line under its upgraded element
;;
;; Taps route through the Tier-0 span-action seam instead of upgrading
;; in place: item checkboxes toggle (`jetpacs.org.checkbox'), and drawer
;; and block header lines get the fold affordance Tier-0's
;; outline-regexp detection cannot see (both reuse `jetpacs.buffer.fold'
;; — `org-cycle' at those lines toggles the drawer/block, verified
;; against emacs-30.1 org-cycle.el).  The footnote/heading/timestamp
;; arms land with their dialog handlers (JA-5d/e).  Everything else —
;; citations, inline math, list markers, src blocks (which org's native
;; fontification already highlights) — renders exactly as the user's
;; font-lock shows it.  If anything in the upgrade pass fails, the
;; buffer falls back to the pure Tier-0 render: this skin can subtract
;; nothing.
;;
;; Budgets: the whole render runs inside ONE `jetpacs-buffer-with-budget'
;; (idempotent — it joins chrome's allowance when a multi_view build is
;; already holding one).  Tier-0 chunks spend spans/bytes themselves;
;; spliced native nodes are charged here — bytes via
;; `jetpacs-buffer-node-bytes', table cells via
;; `jetpacs-buffer-spend-limit' — because GATE 5 counts those aggregates
;; per SurfaceSpec and answers an overrun with a whole-push refusal.
;;
;; Exposure (SPEC 23.1): the buffer's records are superseded ONCE up
;; front, then every chunk and affordance accumulates into the same
;; document scope — so a native node emitted before the first Tier-0
;; chunk cannot have its records wiped by that chunk's supersession.
;; Span-minted taps carry `:args (:buffer NAME :pos POS)' and are
;; recorded by the deferred-exposure walk exactly when their node
;; survives both budgets.  The verbs here register OWNERLESS (the
;; `emacs.buffer.act' precedent): an org buffer renders on whatever
;; surface drills into it — files, the emacs-ui hub, habits — and an
;; owner-scoped registration would answer every foreign-surface tap
;; with a silent `rejected' (the JA-6 audit's dired-cards defect).
;;
;; The `:buffer' args member is the RAW buffer name, exactly as Tier-0
;; ships it for `emacs.buffer.act' — the exposure table and the handler
;; lookup key on the same string, so scrubbing here would break the
;; round trip while the generic verb still carried the raw form.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-element)
(require 'jetpacs-org)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-buffer)
(require 'jetpacs-hypertext)
(require 'jetpacs-async)
;; The dialog handlers must exist before any descriptor naming them can
;; render — loading the skin alone must never mint a dead tap.
(require 'jetpacs-org-dialogs)

;;;; Options

(defcustom jetpacs-org-render-proportional-prose nil
  "When non-nil, org prose renders proportional instead of monospace.
Off by default — Emacs's default face is monospace and so is Orgro's
(one global family, Fira Code), so all-mono IS the faithful mobile org
baseline.  Turning this on clears `jetpacs-buffer-monospace' for the
render and marks `jetpacs-org-render-mono-faces' as code faces, so
everything column-sensitive stays aligned while body text reflows in
the device's proportional face."
  :type 'boolean :group 'jetpacs-org)

(defcustom jetpacs-org-render-mono-faces
  '(org-block org-block-begin-line org-block-end-line org-table
    org-formula org-code org-verbatim org-meta-line)
  "Faces kept monospace when `jetpacs-org-render-proportional-prose' is on."
  :type '(repeat face) :group 'jetpacs-org)

(defvar jetpacs-org-render-hide-widen nil
  "When non-nil, `jetpacs-org-render' omits its narrow→widen affordance.
A host that owns its own back navigation and re-narrows the buffer on
every build binds this — an in-body Widen button would be a confusing
no-op there.")

;;;; Native upgrades: table

(defun jetpacs-org-render--table-aligns (rows)
  "Column alignment list for org table ROWS (from `org-table-to-lisp').
Explicit <l>/<c>/<r> cookie cells win; otherwise org's own numeric
heuristic (`org-table-number-regexp' over at least
`org-table-number-fraction' of a column's non-empty cells ⇒ right).
Returns nil when every column would be plain start-aligned, keeping the
node minimal."
  (let* ((data (seq-remove #'symbolp rows))   ; drop hline markers
         (ncols (apply #'max 0 (mapcar #'length data)))
         (cookie-re "\\`<\\([lcr]\\)[0-9]*>\\'")
         (aligns (make-vector ncols nil))
         interesting)
    (dolist (row data)
      (cl-loop for cell in row and col from 0
               do (let ((cell (string-trim cell)))
                    (when (string-match cookie-re cell)
                      (aset aligns col
                            (pcase (match-string 1 cell)
                              ("l" "start") ("c" "center") ("r" "end")))))))
    (dotimes (col ncols)
      (unless (aref aligns col)
        (let ((total 0) (numeric 0))
          (dolist (row data)
            (let ((cell (string-trim (or (nth col row) ""))))
              (unless (or (string-empty-p cell)
                          (string-match-p cookie-re cell)
                          (string-match-p "\\`<[0-9]+>\\'" cell))
                (cl-incf total)
                (when (string-match-p org-table-number-regexp cell)
                  (cl-incf numeric)))))
          (aset aligns col
                (if (and (> total 0)
                         (>= (/ (float numeric) total)
                             org-table-number-fraction))
                    "end"
                  "start"))))
      (unless (equal (aref aligns col) "start")
        (setq interesting t)))
    (and interesting (append aligns nil))))

(defun jetpacs-org-render--table-node (el)
  "A (NODE . CELL-COUNT) for org table element EL, or nil for table.el.
Rows come from `org-table-to-lisp'; hlines become rules, rows above the
first hline render as the header group (org's own header convention)
with bold cells.  The #+TBLFM line sits outside :contents-end and stays
Tier-0 text.  Inline emphasis inside cells is a documented degrade —
element granularity has no table-cell objects."
  (when (eq (org-element-property :type el) 'org)
    (let* ((lisp (org-table-to-lisp
                  (buffer-substring-no-properties
                   (org-element-property :contents-begin el)
                   (org-element-property :contents-end el))))
           (has-header (and (memq 'hline lisp)
                            (not (eq (car lisp) 'hline))))
           (aligns (and lisp (jetpacs-org-render--table-aligns lisp)))
           (seen-hline nil)
           (cells 0))
      (when lisp
        (cons
         (jetpacs-table
          (mapcar
           (lambda (row)
             (if (eq row 'hline)
                 (progn (setq seen-hline t) (jetpacs-table-rule))
               (let ((header (and has-header (not seen-hline))))
                 (cl-incf cells (length row))
                 (apply #'jetpacs-table-row (if header "header" "data")
                        (mapcar
                         (lambda (cell)
                           (jetpacs-table-cell
                            (list (if header
                                      (jetpacs-span (jetpacs-scalar-text cell)
                                                    :font-weight "bold")
                                    (jetpacs-span
                                     (jetpacs-scalar-text cell))))))
                         row)))))
           lisp)
          :aligns aligns)
         cells)))))

;;;; Native upgrades: images

(defconst jetpacs-org-render--image-link-line-re
  (concat "[ \t]*\\[\\[\\(?:file:\\)?\\([^][]+\\."
          "\\(?:png\\|jpe?g\\|gif\\|webp\\|svg\\|bmp\\)\\)\\]"
          "\\(?:\\[\\([^][]*\\)\\]\\)?\\][ \t]*$")
  "A line that is exactly one image link, description optional.")

(defun jetpacs-org-render--data-uri (path)
  "Local image PATH as a base64 data: URI string, or nil to degrade.
The full gauntlet, every step a silent degrade to Tier-0 text: the
`image'/`image.data' advertisements, the org root allowlist (an org
file may reference ANY path — only allowlisted ones are ever read),
`file-regular-p' on the checked truename (a FIFO under a root hangs
`insert-file-contents' forever — the JA-6 audit's P1-4), the bounded
read, a png/jpeg sniff (SPEC 17.2's guaranteed-decode pair), and the
per-image + frame-budget fit.  The encode passes NO-LINE-BREAK: RFC
4648 standard alphabet, padded, no whitespace — Emacs wraps at column
76 otherwise and the Companion rejects the document."
  (when (and (jetpacs-node-advertised-p "image")
             (jetpacs-feature-advertised-p "image.data"))
    (let* ((abs (expand-file-name
                 path
                 (if buffer-file-name
                     (file-name-directory buffer-file-name)
                   default-directory)))
           (checked (condition-case nil
                        (jetpacs-org--check-file abs)
                      (jetpacs-org-refused nil))))
      (when (and checked (file-regular-p checked))
        (when-let* ((data (jetpacs-hypertext-file-bytes checked))
                    (type (jetpacs-hypertext-sniff-type data)))
          (when (jetpacs-hypertext-image-fits-p data)
            (concat "data:image/" (if (eq type 'png) "png" "jpeg")
                    ";base64," (base64-encode-string data t))))))))

(defun jetpacs-org-render--image-node (el)
  "An image node when paragraph EL is a single standalone image link.
https URLs pass through when the Companion advertises `image.https'
(it fetches them itself); http URLs never upgrade (the advertised form
is https, and silently rewriting the user's URL is not this skin's
call); local paths go through `jetpacs-org-render--data-uri'.  Any
refusal returns nil and the paragraph stays Tier-0 text — with its
link still tappable through `emacs.buffer.act'."
  (save-excursion
    (goto-char (org-element-property :post-affiliated el))
    (when (and (looking-at jetpacs-org-render--image-link-line-re)
               ;; The link line must BE the whole paragraph.
               (>= (line-beginning-position 2)
                   (jetpacs-org-render--visual-end el)))
      (let* ((path (match-string-no-properties 1))
             (desc (match-string-no-properties 2))
             (url (cond
                   ((string-match-p "\\`https://" path)
                    (and (jetpacs-node-advertised-p "image")
                         (jetpacs-feature-advertised-p "image.https")
                         path))
                   ((string-match-p "\\`http://" path) nil)
                   (t (jetpacs-org-render--data-uri path)))))
        (when url
          (jetpacs-image url
                         :content-description
                         (jetpacs-scalar-text
                          (or (and desc (not (string-empty-p desc)) desc)
                              (file-name-nondirectory path)))))))))

;;;; The upgrade pass

(defun jetpacs-org-render--visual-end (el)
  "EL's end position excluding trailing blank lines.
Tier 0 keeps blank lines' vertical space, so an upgrade must not
swallow the blanks org-element folds into an element's :end."
  (save-excursion
    (goto-char (org-element-property :end el))
    (skip-chars-backward " \t\n")
    (min (point-max) (line-beginning-position 2))))

(defun jetpacs-org-render--element-caption (el)
  "The raw #+CAPTION text from EL's affiliated keyword lines, or nil."
  (when (org-element-property :caption el)
    (save-excursion
      (goto-char (org-element-property :begin el))
      (let ((case-fold-search t))
        (when (re-search-forward
               "^[ \t]*#\\+caption\\(?:\\[.*?\\]\\)?:[ \t]*\\(.*\\)$"
               (org-element-property :post-affiliated el) t)
          (let ((cap (string-trim (match-string-no-properties 1))))
            (unless (string-empty-p cap) cap)))))))

;;;; Native upgrades: LaTeX environments (JA-5c)
;;
;; The poc compiled formulas SYNCHRONOUSLY inside the socket filter (15
;; seconds per uncached fragment, N fragments per first push) and
;; shipped file:// URIs.  Rebuilt: the upgrade arm asks `jetpacs-async'
;; and splices a progress node while a `run-at-time' drain — off the
;; jsonrpc dispatch extent — runs ONE `org-create-formula-image' per
;; tick; the result ships as a data: URI.  The module MEMO, not the
;; async table, is the durable cache: the async eviction sweep is a
;; GLOBAL per-push generation sweep, so any other surface pushing twice
;; between org renders evicts the entries — re-entry then re-reports
;; pending for one frame and resolves from the memo without recompiling.
;; Failures memoise too ('fail), so a machine without a TeX toolchain
;; pays one attempt per fragment per session, not one per push.

(defcustom jetpacs-org-render-latex-images t
  "When non-nil, org LaTeX environments render as preview images.
Uses org's own preview pipeline (`org-preview-latex-default-process',
`org-format-latex-options' — scale and colors included), so what the
phone shows is what \\[org-latex-preview] would show.  Only a process
whose output is PNG qualifies — SVG is an active format SPEC 17.2
rejects, and silently overriding the user's configured process is not
this skin's call; a non-PNG process leaves the environment as styled
text.  With no TeX toolchain the environment likewise stays text."
  :type 'boolean :group 'jetpacs-org)

(defcustom jetpacs-org-latex-memo-max 64
  "Successful formula renders kept in the session memo (FIFO evicted).
Failure markers are free — they carry no image bytes."
  :type 'integer :group 'jetpacs-org)

(defvar jetpacs-org-render--latex-memo (make-hash-table :test #'equal)
  "KEY -> (DATA-URI . WIDTH-PX), or `fail'.  The durable formula cache.")

(defvar jetpacs-org-render--latex-order nil
  "Successful memo KEYs, oldest first — the FIFO eviction order.")

(defvar jetpacs-org-render--latex-queue nil
  "Pending compiles: (KEY FRAGMENT BUFFER RESOLVE REJECT), FIFO.")

(defvar jetpacs-org-render--latex-timer nil
  "The armed drain timer, or nil.")

(defun jetpacs-org-render--latex-png-p ()
  "Whether the configured preview process outputs PNG."
  (equal (or (plist-get (cdr (assq org-preview-latex-default-process
                                   org-preview-latex-process-alist))
                        :image-output-type)
             "png")
         "png"))

(defun jetpacs-org-render--latex-safe-options ()
  "`org-format-latex-options', with colors a headless Emacs can resolve.
org's pipeline resolves the symbol `default' through the default face,
whose colors are \"unspecified\" in a batch or daemon session;
`color-values' then returns nil and the render dies on a format error.
Substitute concrete values only in that case — an explicit user color
resolves everywhere and is honored untouched."
  (let ((opts (copy-sequence org-format-latex-options)))
    (cl-flet ((unresolvable-p (c) (not (and (stringp c) (color-values c)))))
      (when (and (eq (plist-get opts :foreground) 'default)
                 (unresolvable-p (face-attribute 'default :foreground nil)))
        (setq opts (plist-put opts :foreground "Black")))
      (when (and (eq (plist-get opts :background) 'default)
                 (unresolvable-p (face-attribute 'default :background nil)))
        (setq opts (plist-put opts :background "Transparent"))))
    opts))

(defun jetpacs-org-render--latex-key (fragment)
  "The memo/async key for FRAGMENT under the current configuration."
  (sha1 (format "%s|%s|%S" fragment
                org-preview-latex-default-process
                (jetpacs-org-render--latex-safe-options))))

(defun jetpacs-org-render--latex-memoize (key value)
  "Store VALUE for KEY in the memo, FIFO-evicting successful entries."
  (when (consp value)
    (setq jetpacs-org-render--latex-order
          (nconc jetpacs-org-render--latex-order (list key)))
    (while (> (length jetpacs-org-render--latex-order)
              (max 1 jetpacs-org-latex-memo-max))
      (remhash (pop jetpacs-org-render--latex-order)
               jetpacs-org-render--latex-memo)))
  (puthash key value jetpacs-org-render--latex-memo))

(defun jetpacs-org-render--latex-compile (fragment buffer)
  "Compile FRAGMENT via org's toolchain; (DATA-URI . WIDTH-PX) or `fail'.
Runs from the drain timer, never the dispatch extent.  Bounded by a 15
second timeout; the temp file never outlives the call; the encoded form
must pass the same per-image fit gauntlet as any other image."
  (condition-case nil
      (with-timeout (15 'fail)
        (let ((tmp (make-temp-file "jetpacs-latex" nil ".png")))
          (unwind-protect
              (progn
                (org-create-formula-image
                 fragment tmp (jetpacs-org-render--latex-safe-options)
                 (and (buffer-live-p buffer) buffer)
                 org-preview-latex-default-process)
                (let* ((data (with-temp-buffer
                               (set-buffer-multibyte nil)
                               (insert-file-contents-literally tmp)
                               (buffer-string)))
                       (width (car (jetpacs-hypertext-png-size data))))
                  (if (and width (jetpacs-hypertext-image-fits-p data))
                      (cons (concat "data:image/png;base64,"
                                    (base64-encode-string data t))
                            width)
                    'fail)))
            (ignore-errors (delete-file tmp)))))
    (error 'fail)))

(defun jetpacs-org-render--latex-drain ()
  "Compile ONE queued formula, settle its async entry, reschedule."
  (setq jetpacs-org-render--latex-timer nil)
  (pcase (pop jetpacs-org-render--latex-queue)
    (`(,key ,fragment ,buffer ,resolve ,reject)
     (let ((result (jetpacs-org-render--latex-compile fragment buffer)))
       (jetpacs-org-render--latex-memoize key result)
       (if (consp result)
           (funcall resolve result)
         ;; Symbol only — never the fragment or the compiler's output
         ;; (SPEC 23.3).
         (funcall reject "latex-failed")))))
  (when jetpacs-org-render--latex-queue
    (jetpacs-org-render--latex-arm)))

(defun jetpacs-org-render--latex-arm ()
  "Arm the drain timer unless it already is."
  (unless (timerp jetpacs-org-render--latex-timer)
    (setq jetpacs-org-render--latex-timer
          (run-at-time 0 nil #'jetpacs-org-render--latex-drain))))

(defun jetpacs-org-render--latex-loader (key fragment buffer)
  "A `jetpacs-async' loader closure for FRAGMENT under KEY."
  (lambda (resolve reject)
    (let ((hit (gethash key jetpacs-org-render--latex-memo)))
      (cond
       ((consp hit) (funcall resolve hit))
       ((eq hit 'fail) (funcall reject "latex-failed"))
       (t
        (setq jetpacs-org-render--latex-queue
              (nconc jetpacs-org-render--latex-queue
                     (list (list key fragment buffer resolve reject))))
        (jetpacs-org-render--latex-arm)
        ;; Cleanup thunk: an evicted entry dequeues its un-started
        ;; compile.  Re-entry recompiles nothing — the memo answers.
        (lambda ()
          (setq jetpacs-org-render--latex-queue
                (cl-delete key jetpacs-org-render--latex-queue
                           :key #'car :test #'equal))))))))

(defun jetpacs-org-render--latex-node (el)
  "The node for latex-environment EL, or nil to keep the text render.
Pending state splices a progress affordance; a failed compile a
truthful caption; a ready formula the width-capped data: image (px≈dp
at org's 140 dpi headless render; capped at 340 so an equation-numbered
full-line environment still fits a phone)."
  (when (and jetpacs-org-render-latex-images
             (fboundp 'org-create-formula-image)
             (jetpacs-node-advertised-p "image")
             (jetpacs-feature-advertised-p "image.data")
             (jetpacs-org-render--latex-png-p))
    (let* ((fragment (org-element-property :value el))
           (key (jetpacs-org-render--latex-key fragment))
           (buffer (current-buffer)))
      (pcase (jetpacs-async (list 'jetpacs-org-latex key)
                            (jetpacs-org-render--latex-loader
                             key fragment buffer))
        (`(pending . ,_)
         (if (jetpacs-node-advertised-p "progress")
             (jetpacs-progress :variant "circular")
           (jetpacs-text "… rendering formula" :style "caption")))
        (`(error . ,_)
         (jetpacs-text "[LaTeX failed]" :style "caption"))
        (`(ready . ,img)
         (jetpacs-with-attrs
          (jetpacs-image (car img) :content-description "LaTeX formula")
          :width (min (cdr img) 340)))))))

(defun jetpacs-org-render--element-hidden-p (beg end)
  "Whether [BEG, END) is ENTIRELY invisible (inside a fold).
Tests every visibility run, not just the first char: org marks a bare
link's `[[' brackets invisible, so a caption-less standalone image
link's element BEGINS at a hidden char while the line is plainly
visible — the poc's first-char check silently skipped exactly that
upgrade.  Fully-hidden extents still skip: Tier 0 drops them, and
upgrading one would leak folded content."
  (let ((p beg))
    (while (and (< p end)
                (let ((iv (get-char-property p 'invisible)))
                  (and iv (invisible-p iv))))
      (setq p (next-single-char-property-change p 'invisible nil end)))
    (>= p end)))

(defun jetpacs-org-render--upgrades ()
  "Upgrade blocks for the current org buffer: sorted (BEG END NODES CELLS).
Each block replaces [BEG, END) of the Tier-0 line render with native
NODES costing CELLS table cells.  Elements inside folded (invisible)
regions are left alone — Tier 0 already drops them, and upgrading would
leak hidden content."
  (let (out)
    (org-element-map (org-element-parse-buffer 'element)
        '(horizontal-rule table latex-environment paragraph)
      (lambda (el)
        (let ((beg (org-element-property :begin el)))
          ;; Hidden-ness is judged over the element's CONTENT chars
          ;; (post-affiliated to visual end): a folded element's :end
          ;; can own a visible trailing blank line past the fold, and
          ;; judging that line visible would leak the folded content.
          (unless (jetpacs-org-render--element-hidden-p
                   (org-element-property :post-affiliated el)
                   (jetpacs-org-render--visual-end el))
            (pcase-let
                ((`(,node ,cells . ,end)
                  (pcase (org-element-type el)
                    ('horizontal-rule
                     (list (jetpacs-divider) 0
                           (jetpacs-org-render--visual-end el)))
                    ('table
                     (when-let* ((n (jetpacs-org-render--table-node el)))
                       (list (car n) (cdr n)
                             (org-element-property :contents-end el))))
                    ('latex-environment
                     (when-let* ((n (jetpacs-org-render--latex-node el)))
                       (list n 0 (jetpacs-org-render--visual-end el))))
                    ('paragraph
                     (when-let* ((n (jetpacs-org-render--image-node el)))
                       (list n 0 (jetpacs-org-render--visual-end el)))))))
              (when node
                (let ((caption (jetpacs-org-render--element-caption el)))
                  ;; With a caption the affiliated lines fold into the
                  ;; upgrade (the caption re-emerges under the node);
                  ;; without one they stay Tier-0 meta text.
                  (push (list (if caption
                                  beg
                                (org-element-property :post-affiliated el))
                              (car end)
                              (delq nil
                                    (list node
                                          (when caption
                                            (jetpacs-text
                                             (jetpacs-scalar-text caption)
                                             :style "caption"))))
                              cells)
                        out))))))))
    (sort (nreverse out) (lambda (a b) (< (car a) (car b))))))

;;;; Span-action routing

(defun jetpacs-org-render--checkbox-at (pos)
  "The (BEG . END) bounds of the item checkbox POS sits inside, or nil.
A cheap char pre-filter guards the org-list predicate (the span seam
consults this per run); the predicate's match data then yields the
exact bracket bounds, so only a tap on the checkbox itself — not the
item's text — counts."
  (and (eq (char-after pos) ?\[)
       (memq (char-after (1+ pos)) '(?\s ?- ?X))
       (eq (char-after (+ pos 2)) ?\])
       (save-excursion
         (goto-char pos)
         (and (org-at-item-checkbox-p)
              (let ((beg (match-beginning 1))
                    (end (match-end 1)))
                (and beg (>= pos beg) (< pos end)
                     (cons beg end)))))))

(defun jetpacs-org-render--span-action (pos buffer-name)
  "Span tap routing for the org skin; nil keeps generic Tier-0 behavior.
Each arm sits behind a one-or-two-char pre-filter, so ordinary runs pay
comparisons, not org regexps (the poc ran the regexps per run).  Links
deliberately fall through — they keep their Tier-0 `emacs.buffer.act'
open behavior.  The drawer/block arms reuse the existing
`jetpacs.buffer.fold' verb: its handler puts point on the line and runs
the buffer's TAB binding, and `org-cycle' there toggles the drawer or
block — the collapse affordance Tier-0's outline-regexp fold detection
cannot see."
  (save-excursion
    (save-match-data
      (goto-char pos)
      (let ((c (char-after pos)))
        (cond
         ;; Footnote reference: [fn:...] opens the footnote dialog.
         ((and (eq c ?\[) (eq (char-after (1+ pos)) ?f)
               (org-in-regexp org-footnote-re)
               (save-match-data (org-footnote-at-reference-p)))
          (jetpacs-action "jetpacs.org.footnote"
                          :args (list :buffer buffer-name :pos pos)))
         ;; Item checkbox: [ ] / [-] / [X].
         ((and (eq c ?\[) (jetpacs-org-render--checkbox-at pos))
          (jetpacs-action "jetpacs.org.checkbox"
                          :args (list :buffer buffer-name :pos pos)))
         ;; Timestamp (active/inactive, planning or body): the one-shot
         ;; editor — Orgro's third structured-edit gesture.
         ((and (memq c '(?< ?\[))
               (let ((n (char-after (1+ pos))))
                 (and n (<= ?0 n ?9)))
               (org-in-regexp org-ts-regexp-both)
               (= (match-beginning 0) pos))
          (jetpacs-action "jetpacs.org.timestamp"
                          :args (list :buffer buffer-name :pos pos)))
         ;; Drawer header (or :END:) line: fold affordance.
         ((and (eq c ?:)
               (save-excursion
                 (beginning-of-line)
                 (looking-at-p org-drawer-regexp)))
          (jetpacs-action "jetpacs.buffer.fold"
                          :args (list :buffer buffer-name :pos pos)))
         ;; Block header line: fold affordance.
         ((and (eq c ?#)
               (let ((case-fold-search t))
                 (save-excursion
                   (beginning-of-line)
                   (looking-at-p "[ \t]*#\\+begin_"))))
          (jetpacs-action "jetpacs.buffer.fold"
                          :args (list :buffer buffer-name :pos pos)))
         ;; Heading tap → the action sheet; a link inside the headline
         ;; keeps its own Tier-0 open behavior.
         ((and (eq (char-after (line-beginning-position)) ?*)
               (org-at-heading-p)
               (not (org-in-regexp org-link-any-re)))
          (jetpacs-action "jetpacs.org.heading"
                          :args (list :buffer buffer-name :pos pos))))))))

;;;; The splice walk

(defun jetpacs-org-render--budget-spent-p ()
  "Whether the shared span or byte allowance has run dry."
  (let ((budget jetpacs-buffer-budget))
    (and budget
         (or (and (car budget) (<= (car budget) 0))
             (and (cdr budget) (<= (cdr budget) 0))))))

(defun jetpacs-org-render--emit-native-p (nodes cells)
  "Charge NODES' bytes and CELLS against the shared budgets.
Non-nil when they fit (and are now spent); nil refuses and spends
NOTHING, so the walk stops with a truthful caption instead of walking
the push into GATE 5's whole-surface refusal."
  (let* ((budget jetpacs-buffer-budget)
         (bytes-left (and budget (cdr budget)))
         (size (apply #'+ (mapcar #'jetpacs-buffer-node-bytes nodes))))
    (cond
     ((and bytes-left (> size bytes-left)) nil)
     ((not (jetpacs-buffer-spend-limit :max_table_cells cells)) nil)
     (t (when bytes-left (setcdr budget (- bytes-left size)))
        t))))

(defun jetpacs-org-render (buffer)
  "Tier-1 render skin for org BUFFER: the Tier-0 line render, upgraded.
See the module commentary for exactly what upgrades; everything else is
the untouched Tier-0 output, and any error in the upgrade scan degrades
to the pure Tier-0 render."
  (with-current-buffer buffer
    (jetpacs-buffer-with-budget
      (let* ((jetpacs-buffer-span-action-function
              #'jetpacs-org-render--span-action)
             (jetpacs-buffer-monospace
              (and (not jetpacs-org-render-proportional-prose)
                   jetpacs-buffer-monospace))
             (jetpacs-buffer-code-faces
              (if jetpacs-org-render-proportional-prose
                  (append jetpacs-org-render-mono-faces
                          jetpacs-buffer-code-faces)
                jetpacs-buffer-code-faces))
             (name (buffer-name))
             (upgrades (condition-case nil
                           (jetpacs-org-render--upgrades)
                         (error nil)))
             (pos (point-min))
             (dropped nil)
             out)
        ;; Supersede this buffer's records ONCE, up front: later chunks
        ;; and affordances accumulate into the same document scope, so a
        ;; native node emitted before the first Tier-0 chunk keeps its
        ;; records (`jetpacs-buffer-forget-exposed' is first-clear-wins
        ;; inside one `jetpacs-buffer-with-budget' document).
        (jetpacs-buffer-forget-exposed name)
        (cl-block walk
          (dolist (up upgrades)
            (pcase-let ((`(,beg ,end ,nodes ,cells) up))
              (when (>= beg pos)
                (when (> beg pos)
                  (setq out (nconc out (jetpacs-buffer-render-region
                                        name pos beg)))
                  ;; A spent budget already captioned itself in Tier-0.
                  (when (jetpacs-org-render--budget-spent-p)
                    (cl-return-from walk)))
                (if (jetpacs-org-render--emit-native-p nodes cells)
                    (setq out (nconc out nodes))
                  (setq dropped t)
                  (cl-return-from walk))
                (setq pos end))))
          (when (< pos (point-max))
            (setq out (nconc out (jetpacs-buffer-render-region
                                  name pos (point-max))))))
        (when dropped
          (setq out (nconc out (list (jetpacs-text
                                      "… output truncated (surface budget)"
                                      :style "caption")))))
        ;; A narrowed buffer shows only its subtree; prepend a widen
        ;; affordance so the focus is reversible without leaving the view.
        (when (and (not jetpacs-org-render-hide-widen) (buffer-narrowed-p))
          (jetpacs-buffer-expose-buffer name "jetpacs.org.widen")
          (setq out (cons (jetpacs-button
                           "⤢ Widen"
                           (jetpacs-action "jetpacs.org.widen"
                                           :args (list :buffer name))
                           :variant "tonal")
                          out)))
        out))))

(jetpacs-render-buffer-register 'org-mode #'jetpacs-org-render)

;;;; The two verbs
;; Registered OWNERLESS — see the module commentary.  Gate order is the
;; sections template: argument shape → 14.5 staleness → 23.1 exposure →
;; effect, synchronous, then the deferred re-push of the tap's surface.

(defun jetpacs-org-render--checkbox (args params)
  "Toggle the checkbox at the tapped position; SPEC 14.4 status."
  (let* ((name (plist-get args :buffer))
         (pos (plist-get args :pos))
         (buf (and (stringp name) (get-buffer name))))
    (cond
     ((not (and buf (integerp pos))) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-buffer-exposed-p name pos "jetpacs.org.checkbox"))
      'rejected)
     (t
      (with-current-buffer buf
        (org-with-wide-buffer
         ;; Re-verify before mutating: a stale surface must never strike
         ;; arbitrary text (the position may have rotted since render).
         (if (not (jetpacs-org-render--checkbox-at pos))
             'stale
           (goto-char pos)
           (org-toggle-checkbox)     ; statistics cookies update via org
           (jetpacs-org-cache-invalidate)
           (when buffer-file-name (jetpacs-org-defer-save))
           (jetpacs-buffer-defer-refresh (plist-get params :surface))
           'accepted)))))))

(defun jetpacs-org-render--widen (args params)
  "Widen the narrowed buffer the render offered the affordance for."
  (let* ((name (plist-get args :buffer))
         (buf (and (stringp name) (get-buffer name))))
    (cond
     ((not buf) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-buffer-exposed-buffer-p name "jetpacs.org.widen"))
      'rejected)
     (t
      (with-current-buffer buf (widen))
      (jetpacs-buffer-defer-refresh (plist-get params :surface))
      'accepted))))

(jetpacs-defaction "jetpacs.org.checkbox" #'jetpacs-org-render--checkbox)
(jetpacs-defaction "jetpacs.org.widen" #'jetpacs-org-render--widen)

;;;; The JA-6 files seams (rendered⇄plain, toolbar, FAB, after-save)
;;
;; JA-6's tap-to-open path builds the PLAIN editor screen and publishes
;; five seams; the org experience claims `.org' paths through them,
;; using only public names.  The per-path VIEW MODE decides which face
;; a file shows: `rendered' (default — the body seam replaces the
;; editor with this skin's output) or `plain' (the body function
;; passes, files builds its own editor, which then picks up the org
;; toolbar through the toolbar seam).  The actions seam contributes
;; the toggle; the FAB seam the add-heading affordance; the after-save
;; hook busts the org cache when a device-side save lands on a `.org'.
;; Seam functions are PURE BUILDERS — they must never push (the JA-6
;; audit names a pushing body function as unexplored territory).

(defvar jetpacs-org-render--files-mode (make-hash-table :test #'equal)
  "PATH -> `rendered' | `plain'.  Absent means `rendered' for org files.")

(defun jetpacs-org-render--org-path-p (path)
  (and (stringp path)
       (string-suffix-p ".org" path t)))

(defun jetpacs-org-render--files-rendered-p (path)
  (and (jetpacs-org-render--org-path-p path)
       (not (eq (gethash path jetpacs-org-render--files-mode) 'plain))))

(defun jetpacs-org-render--files-body (path)
  "The body seam: the rendered org view, or nil to pass to the editor."
  (when (jetpacs-org-render--files-rendered-p path)
    (let ((buf (find-file-noselect path t)))
      (with-current-buffer buf
        (unless (derived-mode-p 'org-mode) (org-mode)))
      (apply #'jetpacs-column (jetpacs-org-render buf)))))

(defun jetpacs-org-render--files-actions (path)
  "The actions seam: the rendered⇄plain toggle icon for org paths."
  (when (jetpacs-org-render--org-path-p path)
    (list (jetpacs-icon-button
           (if (jetpacs-org-render--files-rendered-p path)
               "edit" "preview")
           (jetpacs-action "jetpacs.org.view-mode"
                           :args (list :path path))
           :content-description
           (if (jetpacs-org-render--files-rendered-p path)
               "Edit as text" "Show rendered")))))

(defun jetpacs-org-render--files-toolbar (path)
  "The toolbar seam: the org toolbar on the plain editor."
  (when (jetpacs-org-render--org-path-p path)
    (jetpacs-org-toolbar)))

(defun jetpacs-org-render--files-fab (path)
  "The FAB seam: the add-heading affordance (mint + record atomic)."
  (when (jetpacs-org-render--org-path-p path)
    (jetpacs-icon-button
     "post_add"
     (jetpacs-org-add-heading-descriptor
      (buffer-name (find-file-noselect path t)))
     :content-description "Add heading")))

(defun jetpacs-org-render--files-after-save (truename)
  "The after-save hook: a device-side org save busts the engine memo."
  (when (jetpacs-org-render--org-path-p truename)
    (jetpacs-org-cache-invalidate)))

(defun jetpacs-org-render--view-mode (args params)
  "Flip the per-path view mode.  The worst a forged path can do is
flip a bit for a file nobody shows — the screens re-derive everything
from their own state on the deferred re-push."
  (let ((path (plist-get args :path)))
    (cond
     ((not (jetpacs-org-render--org-path-p path)) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     (t
      (puthash path
               (if (jetpacs-org-render--files-rendered-p path)
                   'plain 'rendered)
               jetpacs-org-render--files-mode)
      (jetpacs-buffer-defer-refresh (plist-get params :surface))
      'accepted))))

(jetpacs-defaction "jetpacs.org.view-mode" #'jetpacs-org-render--view-mode)

;; Compile-time declarations for the files seams (loaded lazily below).
(defvar jetpacs-files-editor-toolbar-function)
(defvar jetpacs-files-editor-fab-function)
(declare-function jetpacs-org-toolbar "jetpacs-org-toolbar")

(with-eval-after-load 'jetpacs-files
  (require 'jetpacs-org-toolbar)
  (add-hook 'jetpacs-files-editor-body-functions
            #'jetpacs-org-render--files-body)
  (add-hook 'jetpacs-files-editor-actions-functions
            #'jetpacs-org-render--files-actions)
  (add-hook 'jetpacs-files-after-save-hook
            #'jetpacs-org-render--files-after-save)
  ;; Single-function seams: claim politely, chaining any prior holder.
  (let ((prev (bound-and-true-p jetpacs-files-editor-toolbar-function)))
    (setq jetpacs-files-editor-toolbar-function
          (lambda (path)
            (or (jetpacs-org-render--files-toolbar path)
                (and prev (funcall prev path))))))
  (let ((prev (bound-and-true-p jetpacs-files-editor-fab-function)))
    (setq jetpacs-files-editor-fab-function
          (lambda (path)
            (or (jetpacs-org-render--files-fab path)
                (and prev (funcall prev path)))))))

;;;; Reset / unload

(defun jetpacs-org-render-reset ()
  "Reset render-module state: LaTeX memo/queue/timer, view modes."
  (clrhash jetpacs-org-render--latex-memo)
  (setq jetpacs-org-render--latex-order nil
        jetpacs-org-render--latex-queue nil)
  (when (timerp jetpacs-org-render--latex-timer)
    (cancel-timer jetpacs-org-render--latex-timer))
  (setq jetpacs-org-render--latex-timer nil)
  (clrhash jetpacs-org-render--files-mode))

(defun jetpacs-org-render-unload-function ()
  "Unload hygiene: deregister the skin, the verbs and the seams."
  (setq jetpacs-render-buffer-functions
        (assq-delete-all 'org-mode jetpacs-render-buffer-functions))
  (jetpacs-undefaction "jetpacs.org.checkbox")
  (jetpacs-undefaction "jetpacs.org.widen")
  (jetpacs-undefaction "jetpacs.org.view-mode")
  (when (boundp 'jetpacs-files-editor-body-functions)
    (remove-hook 'jetpacs-files-editor-body-functions
                 #'jetpacs-org-render--files-body)
    (remove-hook 'jetpacs-files-editor-actions-functions
                 #'jetpacs-org-render--files-actions)
    (remove-hook 'jetpacs-files-after-save-hook
                 #'jetpacs-org-render--files-after-save))
  (jetpacs-org-render-reset)
  nil)

(provide 'jetpacs-org-render)
;;; jetpacs-org-render.el ends here
