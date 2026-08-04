;;; jetpacs-sections.el --- Generic magit-section substrate (Tier 0.5) -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Tier 0.5: one renderer for every buffer built on the magit-section
;; library — magit status/log/diff/refs, forge topics, kubernetes.el, and
;; every `taxy-magit-section' consumer.  ONE renderer per framework, and
;; every package built on it arrives pre-skinned.
;;
;; Under Tier 0 these buffers already render acceptably.  What this
;; substrate adds: the section TREE becomes real `collapsible' cards —
;; folding is instant and client-side, no round trip — and a long-press
;; on any header offers that section's OWN key bindings, so the phone
;; gets magit's per-section verbs without one command name ever crossing
;; the wire (the wire carries keys and positions; the buffer's keymaps
;; decide meaning).
;;
;; FOLD STATE IS DEVICE-LOCAL, deliberately.  Emacs's `hidden' bit seeds
;; the FIRST snapshot of a card and nothing after it: SPEC 17.3 makes
;; `collapsible.collapsed' seed-only for a presentation identity, so
;; local expansion survives a repeated authored value — and since the
;; card id is deliberately stable across refreshes (that is what keeps
;; fold state attached to the same section), a changed `hidden' bit has
;; no effect on a card the device has already seen.  That is the right
;; trade: folding stays instant and round-trip-free, and the phone's
;; view of a long magit-status is not yanked around by an unrelated
;; refresh in Emacs.  The alternative — folding `hidden' into the id —
;; would mint a new identity on every toggle and discard all other
;; device-local state for that card along with it.
;;
;; The library is third-party (NonGNU ELPA): nothing here requires it.
;; Reading the tree uses `slot-value' (eieio is built-in), and registration
;; waits for the library via `with-eval-after-load'.
;;
;; Body lines ride the Tier 0 line-span builder unchanged (monospace and
;; colors on — diffs keep their +/- shading, taps keep working), so this
;; file knows only the tree shape.  A buffer whose root section is missing
;; falls through to Tier 0 — the substrate is polish, never a prerequisite.
;;
;; Rung JC-3a of docs/PLAN-jetpacs-consumers.md.  Ported from poc-v1 with
;; the span surgery moved alist -> plist, plus three conformance changes:
;;
;; - The retargeted taps are RE-EXPOSED under their new verb.  Exposure
;;   records are per-action (SPEC 23.1), and the Tier-0 builder exposed
;;   these positions for `emacs.buffer.act'; rewriting the descriptor to
;;   `sections.visit' without re-exposing would make every tap refused.
;; - `sections.menu' no longer calls `completing-read' in the handler.
;;   That blocks the jsonrpc dispatch extent (decision D2), so the
;;   Companion would never learn the outcome.  The picker is an EBP dialog.
;; - Optional node types degrade to Core (SPEC 16.2).

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'eieio)                ; slot-value on section objects (built-in)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-commands)     ; jetpacs-command-visible-p (JA-3a)
(require 'jetpacs-buffer)       ; line spans, dispatch registry, exposure
(require 'jetpacs-results)      ; the region-view seam + RET resolution

;; The magit-section library, never required from core:
(declare-function magit-section-ident "ext:magit-section" (section))
(declare-function magit-section-hidden "ext:magit-section" (section))
(defvar magit-root-section)

;; --- Configuration -----------------------------------------------------------

(defcustom jetpacs-sections-max-lines 500
  "Total body-line budget for one rendered section buffer.
Past the budget, remaining sections still render their headers (the tree
stays navigable) but bodies are elided with a note."
  :type 'integer :group 'jetpacs)

(defcustom jetpacs-sections-max-sections 300
  "Cap on the number of section CARDS one render emits.
`jetpacs-sections-max-lines' bounds body lines only — a card's header,
its `collapsible' wrapper and its `rich_text' are nodes too, and a
`magit-log' with thousands of commits is thousands of sections whose
bodies are one line each.  Without this the line budget is never reached
while the node count sails past SPEC 4.5's ceiling and the whole push is
refused."
  :type 'integer :group 'jetpacs)

;; The per-render id table this module used to own is now the floor's
;; `jetpacs-node-id-claims' (SPEC 16.1 scopes uniqueness to the whole
;; DOCUMENT, and chrome puts N renders in one) — the suffix algorithm
;; moved to `jetpacs-claim-node-id' unchanged, plus a 4.4 length clamp.

(defvar jetpacs-sections--cards 0
  "Cards emitted so far in this render (see `jetpacs-sections-max-sections').")

(defcustom jetpacs-sections-menu-denylist
  '(;; Not covered by `jetpacs-suppressed-commands' (its `\\=`mouse-'
    ;; regexp misses this magit-prefixed mouse command).
    magit-mouse-toggle-section
    ;; Destructive, and NOT offerable over the wire.  A dialog button
    ;; carries no SPEC 14.1 `confirm' — `jetpacs-dialog-submit' has no
    ;; such member — so a mis-tap on a phone would delete a branch or
    ;; move a ref with nothing standing in the way.  Symbols verified
    ;; against live magit: `k' is `magit-delete-thing', NOT
    ;; `magit-discard', and `x' is `magit-reset-quickly'.
    magit-delete-thing magit-discard
    magit-reset magit-reset-quickly
    magit-reset-hard magit-reset-soft magit-reset-mixed magit-reset-index
    magit-branch-delete magit-tag-delete magit-remote-remove
    magit-stash-drop magit-stash-clear
    magit-file-delete magit-revert magit-revert-no-commit)
  "Commands never offered in the section context menu.
This list is the SECTIONS-LOCAL residue after the JA-3a consolidation:
generic keymap noise (self-insert, argument readers, quit and mouse
commands) moved to `jetpacs-suppressed-commands', consulted here
through `jetpacs-command-visible-p'.  What stays is semantically
different — a no-confirm-affordance SAFETY list.  `magit-discard' is
rightly unofferable from a long-press menu, where a mis-tap is one
finger-slip away, yet remains runnable from the device M-x, where
require-match means the user typed it in full."
  :type '(repeat function) :group 'jetpacs)

;; --- Reading the tree --------------------------------------------------------

(defun jetpacs-sections--root ()
  "The current buffer's magit-section root, or nil."
  (and (featurep 'magit-section)
       (bound-and-true-p magit-root-section)))

(defun jetpacs-sections--pos (sec slot)
  "Marker SLOT of section SEC as a position, or nil."
  (let ((m (slot-value sec slot)))
    (and (markerp m) (marker-position m))))

(defun jetpacs-sections--slot (sec slot)
  "SLOT of section SEC.
The slot name crosses a function boundary deliberately: the
magit-section class is never loaded at compile time, and some slot names
\(`hidden', `washer') are declared by no compile-time class — a constant
name at the call site draws an unknown-slot warning."
  (slot-value sec slot))

(defun jetpacs-sections--hidden-p (sec)
  "Whether SEC is folded in Emacs.
Prefers the library's own accessor, which is what
`jetpacs-buffer--fold-state' already uses for the same question — two
modules reading one piece of state two different ways is a drift waiting
to happen, and the accessor is the supported API.  Falls back to the raw
slot for a section object built by something that does not define it."
  (if (fboundp 'magit-section-hidden)
      (magit-section-hidden sec)
    (jetpacs-sections--slot sec 'hidden)))

(defun jetpacs-sections--id (sec)
  "A stable collapsible id for SEC: its ident path, hashed, deduplicated.
`magit-section-ident' is the library's own stable identity (it survives a
refresh, which keeps client-side fold state attached to the same
section).  Falls back to the start position.

Neither source is guaranteed unique — the ident repeats across taxy and
forge groupings, and two sections sharing a `start' marker produce the
same fallback — so a collision within one render is suffixed.  SPEC 16.1
answers a duplicate id with `1201' for the entire update, so this is not
a cosmetic concern: one repeat costs the whole surface.

The suffix only moves the SECOND and later claimants, so the first
occurrence keeps the stable id and its device-local fold state."
  (let ((base (or (condition-case nil
                      (md5 (format "%S" (magit-section-ident sec)))
                    (error nil))
                  (format "sec-%s" (jetpacs-sections--pos sec 'start)))))
    (jetpacs-claim-node-id base)))

;; --- Span surgery (format 6: spans are PLISTS) -------------------------------

(defun jetpacs-sections--strip-taps (spans)
  "Copies of SPANS without their tap actions.
For a collapsible header, where a tap must mean fold/unfold rather than
the span's own action.  Spans are plists in format 6, so this rebuilds
each without `:on_tap' instead of `assq-delete-all'."
  (mapcar (lambda (sp)
            (let (out)
              (cl-loop for (k v) on sp by #'cddr
                       unless (eq k :on_tap)
                       do (setq out (nconc out (list k v))))
              out))
          spans))

(defun jetpacs-sections--retarget-taps (spans name)
  "SPANS with their generic tap actions re-pointed at `sections.visit'.
The Tier 0 builder wires taps to `emacs.buffer.act', which runs the RET
command in place — in a magit buffer that visits a thing by popping a
desktop window the phone never sees.  `sections.visit' runs the same
command under the follow shim and shows the destination in the region
view.  Fold-affordance taps and untapped spans pass through untouched.

Re-exposes each retargeted position under the NEW verb: SPEC 23.1
records are per-action, and the Tier-0 builder exposed these positions
for `emacs.buffer.act' only, so without this every retargeted tap would
be refused."
  (mapcar
   (lambda (sp)
     (let ((tap (plist-get sp :on_tap)))
       (if (not (equal (plist-get tap :action) "emacs.buffer.act"))
           sp
         (let* ((args (plist-get tap :args))
                (pos (plist-get args :pos))
                (copy (copy-sequence sp)))
           (when (integerp pos)
             (jetpacs-buffer-expose name pos "sections.visit"))
           (plist-put copy :on_tap
                      (jetpacs-action "sections.visit" :args args))))))
   spans))

;; --- Emitting nodes ----------------------------------------------------------

(defun jetpacs-sections--spans (bol eol name)
  "Tier-0 spans for [BOL, EOL) WITHOUT their automatic exposure records.
This substrate STRIPS the tap on headers and RE-POINTS it at
`sections.visit\' on body lines, so the generic `emacs.buffer.act\'
record the walk writes must not stand — see
`jetpacs-buffer-with-scratch-exposure\'.  This file then exposes only
the verbs it actually offers."
  (jetpacs-buffer-with-scratch-exposure
    (jetpacs-buffer-line-spans bol eol name)))

(defun jetpacs-sections--rich (spans)
  "SPANS as a `rich_text' node, or a Core `text' when unadvertised (16.2).
Draws on the shared SPEC 4.5 span allowance: `max_rich_spans' is an
aggregate across one SurfaceSpec, and this skin builds its spans outside
`jetpacs-buffer--render-region', so nothing else would debit them."
  (let ((spans (jetpacs-buffer-spend-spans spans)))
    (if (jetpacs-node-advertised-p "rich_text")
        (jetpacs-rich-text spans)
      (jetpacs-text (mapconcat (lambda (s) (or (plist-get s :text) "")) spans "")
                    :style "mono"))))

(defun jetpacs-sections--header-node (sec name)
  "The always-visible header node for SEC: its heading line's own spans
\(faces intact — branch colors, file names), taps stripped."
  (let* ((start (jetpacs-sections--pos sec 'start))
         (spans (save-excursion
                  (goto-char start)
                  (jetpacs-sections--spans start (line-end-position) name))))
    (jetpacs-sections--rich (or (jetpacs-sections--strip-taps spans)
                                (list (jetpacs-span " "))))))

(defun jetpacs-sections--body-lines (beg end name budget)
  "Body lines [BEG, END) as nodes, consuming BUDGET (a cons cell).
Taps are visit-routed.  Once the budget is spent, emits one elision note
and stops."
  (let (nodes)
    (save-excursion
      (goto-char beg)
      (while (< (point) end)
        (let ((bol (line-beginning-position))
              (eol (min (line-end-position) end)))
          (cond
           ((<= (car budget) 0)
            ;; Latched in the budget's `cdr': this branch is reached once
            ;; per REMAINING SECTION, so a large `magit-status' otherwise
            ;; emits one elision caption per section all the way down.
            (unless (cdr budget)
              (setcdr budget t)
              (push (jetpacs-text
                     (format "… %d more line(s) in Emacs"
                             (count-lines (point) end))
                     :style "caption")
                    nodes))
            (goto-char end))
           (t
            (when (< bol eol)
              (let ((spans (jetpacs-sections--spans bol eol name)))
                (when spans
                  (push (jetpacs-sections--rich
                         (jetpacs-sections--retarget-taps spans name))
                        nodes))))
            (cl-decf (car budget))
            (forward-line 1))))))
    (nreverse nodes)))

(defun jetpacs-sections--child-nodes (sec name budget begin)
  "SEC's revealed content from BEGIN to its end: own body lines
interleaved with child sections, in buffer order."
  (let ((end (or (jetpacs-sections--pos sec 'end) begin))
        (pos begin)
        nodes)
    (dolist (child (jetpacs-sections--slot sec 'children))
      (let ((cstart (jetpacs-sections--pos child 'start))
            (cend (jetpacs-sections--pos child 'end)))
        (when (and cstart (> cstart pos))
          (setq nodes (nconc nodes (jetpacs-sections--body-lines
                                    pos cstart name budget))))
        (setq nodes (nconc nodes (jetpacs-sections--emit child name budget)))
        (setq pos (or cend pos))))
    (when (< pos end)
      (setq nodes (nconc nodes (jetpacs-sections--body-lines
                                pos end name budget))))
    nodes))

(defun jetpacs-sections--card (sec name start header children)
  "A collapsible card for SEC, or a Core fallback when unadvertised (16.2)."
  (if (not (jetpacs-node-advertised-p "collapsible"))
      ;; Core: no `collapsible', so there is no fold affordance to give.
      ;; A section Emacs has FOLDED renders header-only — showing its body
      ;; would put content on the phone that the user has explicitly
      ;; collapsed, and with no way to re-collapse it.  NO `sections.menu'
      ;; exposure on this path either: it emits no long-tap, and SPEC 23.1
      ;; records authorize what the document actually offers, never an
      ;; affordance absent from it.
      (if (jetpacs-sections--hidden-p sec)
          header
        (apply #'jetpacs-column header children))
    (jetpacs-buffer-expose name start "sections.menu")
    (apply #'jetpacs-collapsible
           (jetpacs-sections--id sec) header
           (append children
                   (list :collapsed
                         ;; Seeds the FIRST snapshot only (SPEC 17.3);
                         ;; fold is device-local thereafter — see the
                         ;; commentary.
                         (jetpacs-bool (jetpacs-sections--hidden-p sec))
                         :on-long-tap
                         (jetpacs-action "sections.menu"
                                         :args (list :buffer name
                                                     :pos start)))))))

(defun jetpacs-sections--emit (sec name budget)
  "Section SEC as a list of nodes.
A section with a heading and content becomes a collapsible card (fold
state mirroring Emacs's, long-press opening the section menu); a bare
heading becomes its line, taps intact; a heading-less container is
transparent — only its children show."
  (let* ((start (jetpacs-sections--pos sec 'start))
         (content (jetpacs-sections--pos sec 'content))
         (end (jetpacs-sections--pos sec 'end))
         (children (jetpacs-sections--slot sec 'children)))
    (cond
     ;; magit leaves `end' unset while a section body is being inserted,
     ;; so a push racing `magit-refresh' sees nil markers.  Without this
     ;; the arithmetic below signals and takes the entire surface down.
     ((null start) nil)
     ;; SPEC 4.5: past the card cap the tree stops entirely.  Emitting
     ;; headers-only would still be one node per section, which is the
     ;; thing the cap exists to bound.
     ((>= jetpacs-sections--cards jetpacs-sections-max-sections)
      (when (= jetpacs-sections--cards jetpacs-sections-max-sections)
        (cl-incf jetpacs-sections--cards)   ; latch: one note per render
        (list (jetpacs-text
               (format "… more sections in Emacs (showing first %d)"
                       jetpacs-sections-max-sections)
               :style "caption"))))
     ((null end)
      (list (jetpacs-sections--rich
             (list (jetpacs-span "… section still loading" :mono t)))))
     ;; Heading + revealed content -> a collapsible card.
     ((and content (< content end))
      (cl-incf jetpacs-sections--cards)
      (list (jetpacs-sections--card
             sec name start
             (jetpacs-sections--header-node sec name)
             (jetpacs-sections--child-nodes sec name budget content))))
     ;; Unwashed lazy section: content == end with a washer pending.  A
     ;; card whose stub child runs the buffer's own fold toggle — showing
     ;; the section washes it in Emacs, and the refresh re-push renders
     ;; the real body.
     ((and content (jetpacs-sections--slot sec 'washer))
      (progn
        (cl-incf jetpacs-sections--cards)
        (jetpacs-buffer-expose name start "jetpacs.buffer.fold")
        (list (jetpacs-sections--card
               sec name start
               (jetpacs-sections--header-node sec name)
               (list (jetpacs-sections--rich
                      (list (jetpacs-span
                             "Tap to load…"
                             :on-tap (jetpacs-action
                                      "jetpacs.buffer.fold"
                                      :args (list :buffer name
                                                  :pos start))))))))))
     ;; Empty section, or a bare heading -> its line, taps intact.
     (content (jetpacs-sections--body-lines start end name budget))
     ;; Heading-less container (the root's shape) -> children only.
     ((and (null content) children)
      (jetpacs-sections--child-nodes sec name budget start))
     (t (jetpacs-sections--body-lines start end name budget)))))

(defun jetpacs-sections-render (buf)
  "Tier 0.5 renderer for magit-section buffers: the tree as collapsible
cards.  Falls through to Tier 0 when the buffer has no section root."
  (with-current-buffer buf
    ;; Section markers address the whole buffer; a narrowed accessible
    ;; portion would put them out of range and truncate the tree.
    (save-restriction
      (widen)
      (jetpacs-sections--render-1 buf))))

(defun jetpacs-sections--render-1 (buf)
  "The body of `jetpacs-sections-render', run widened."
  (with-current-buffer buf
    (let ((root (jetpacs-sections--root)))
      (if (or (null root) (< (buffer-size) 1))
          (jetpacs-buffer-render buf)
        ;; The scanner must see the whole tree, including bodies Emacs has
        ;; folded away (`hidden' mirrors into :collapsed instead) — an
        ;; invisibility spec of nil makes `invisible' props inert for the
        ;; walk without touching buffer state.
        (let ((budget (cons jetpacs-sections-max-lines nil))
              (name (buffer-name buf))
              ;; SPEC 16.1 uniqueness is DOCUMENT state: join the table
              ;; in force (the shell binds one around every root build) —
              ;; a fresh one here would re-create the one-buffer-per-
              ;; surface assumption chrome broke.  Standalone renders get
              ;; their own, exactly as before.  The card cap stays
              ;; per-render.
              (jetpacs-node-id-claims
               (or jetpacs-node-id-claims
                   (make-hash-table :test #'equal)))
              (jetpacs-sections--cards 0))
          ;; This render supersedes the last one's tap targets.
          (jetpacs-buffer-forget-exposed name)
          (or (jetpacs-buffer-with-budget
                ;; The scanner must see the whole tree, including bodies
                ;; Emacs has folded away (`hidden' seeds :collapsed
                ;; instead) — an invisibility spec of nil makes
                ;; `invisible' props inert for the walk without touching
                ;; buffer state.  Scoped to the WALK only: the Tier-0
                ;; fallback below must NOT run under it, or a fallback
                ;; render paints every folded body inline while still
                ;; drawing the fold affordance.
                (let ((buffer-invisibility-spec nil))
                  ;; The tree is third-party eieio read through
                  ;; `slot-value': an unbound slot, a missing slot on an
                  ;; exotic section class, or a mid-refresh nil marker
                  ;; must cost this SKIN, never the push.
                  (condition-case err
                      (jetpacs-sections--emit root name budget)
                    (error
                     (message "jetpacs-sections: tree walk failed (%s); \
falling back to Tier 0" (jetpacs--error-label err))
                     nil))))
              (jetpacs-buffer-render buf)))))))

;; --- Visiting the thing at a row ---------------------------------------------

(defun jetpacs-sections--section-buffer (name)
  "The live magit-section buffer NAME, or nil (SPEC 23.1)."
  (let ((buf (and (stringp name) (get-buffer name))))
    (and buf
         (with-current-buffer buf
           (and (derived-mode-p 'magit-section-mode)
                (jetpacs-sections--root)))
         buf)))

(defun jetpacs-sections--visit (buf pos)
  "Follow the thing at POS in section buffer BUF.
Returns non-nil when the command left the buffer (its destination is
shown in the region view), nil when it acted in place — stage, unstage,
toggle — and SIGNALS when the command itself failed.

The shimmed replay itself lives in `jetpacs-results-follow': it is the
same operation the results skin performs, down to the ON-ERROR thunk that
keeps a signalling command from reading as \"acted in place\", and one
implementation means a fix to that reasoning lands once rather than
twice."
  (when-let* ((dest (jetpacs-results-follow buf pos)))
    (pcase-let ((`(,beg ,end ,label ,point)
                 (jetpacs-results-region-around (car dest) (cdr dest))))
      (funcall jetpacs-results-visit-region-function
               (buffer-name (car dest)) beg end label point))
    t))

(jetpacs-defaction "sections.visit"
  ;; BUFFER must be a live magit-section buffer, POS a row this render
  ;; actually offered.  Follow if the row's command jumps; re-push if it
  ;; acted in place (stage, toggle) or could not follow.
  (lambda (args params)
    (let* ((name (plist-get args :buffer))
           (pos (plist-get args :pos))
           (buf (jetpacs-sections--section-buffer name))
           (jetpacs-results-event-surface (plist-get params :surface)))
      (cond
       ;; `integerp', not `numberp': a float clears the type gate and
       ;; then misses `jetpacs-buffer-exposed-p''s `eql' hash, so it
       ;; would be refused for the wrong reason.
       ((not (and buf (integerp pos))) 'rejected)
       ;; 14.1 -> 14.5 -> 23.1, matching `jetpacs-buffer--tap-status'.
       ;; Stale FIRST is the better answer as well as the house order: a
       ;; magit refresh moves every offset, so an event tapped against the
       ;; previous snapshot deserves re-presentable `stale' rather than
       ;; terminal `rejected' from the exposure gate it now misses.
       ((jetpacs-event-stale-p params) 'stale)
       ((not (jetpacs-buffer-exposed-p name pos "sections.visit")) 'rejected)
       (t
        ;; Synchronous, so `accepted' names a completed effect (14.4).
        ;; A command that acted in place (stage/toggle) shows nothing new
        ;; by itself, so fall back to a deferred re-push.
        (unless (jetpacs-sections--visit buf pos)
          (jetpacs-sections--refresh params))
        'accepted)))))

(defun jetpacs-sections--refresh (params)
  "Re-push the surface the event came from, deferred (SPEC 14.4/D1)."
  (jetpacs-buffer-defer-refresh (plist-get params :surface)))

(defun jetpacs-sections--menu-label (cmd)
  "A human label for command CMD: prefix-stripped, dashes to spaces."
  (let ((s (symbol-name cmd)))
    (dolist (prefix '("magit-section-" "magit-" "forge-" "kubernetes-"))
      (when (string-prefix-p prefix s)
        (setq s (substring s (length prefix)))))
    (capitalize (string-replace "-" " " s))))

(defcustom jetpacs-sections-menu-mode-keys '("s" "u" "c" "RET")
  "Keys offered from the MAJOR MODE's map in the section menu.

An allowlist, not a denylist, and that inversion is the whole point.  A
section's own text-property keymap is small and genuinely per-section, so
everything offerable in it is offered.  A mode map is the buffer's ENTIRE
user interface — scanning magit-status wholesale yields 60 candidates,
which is magit's keymap, not \"this section's verbs\", and no use at all
as a phone long-press.

The default is the handful that conventionally act on the thing at point
\(stage, unstage, commit, visit in magit).  Keys, not commands, so this
stays framework-generic: forge, kubernetes.el and taxy consumers bind
their own commands to the same keys.  Add to it freely — but note that
whatever is offerable here becomes replayable (SPEC 23.2 re-derives from
this same function), so `jetpacs-sections-menu-denylist' still applies."
  :type '(repeat string) :group 'jetpacs)

(defcustom jetpacs-sections-menu-max 16
  "Cap on entries in one section menu.
A backstop: a future keymap should degrade to a usable dialog, never a
scrolling wall of buttons."
  :type 'integer :group 'jetpacs)

(defun jetpacs-sections--map-candidates (km cands &optional only-keys)
  "Collect offerable single-key bindings from keymap KM into CANDS."
  (when (keymapp km)
    (map-keymap
     (lambda (event binding)
       (when (and (jetpacs-command-visible-p binding)
                  (not (memq binding jetpacs-sections-menu-denylist))
                  (or (and (integerp event) (< 31 event 127))
                      (memq event '(return tab))))
         (let ((key (key-description (vector event))))
           (when (or (null only-keys) (member key only-keys))
             ;; A text-property map SHADOWS the mode map, so a key
             ;; already claimed by a nearer keymap keeps its nearer
             ;; meaning.
             (unless (rassoc key cands)
               (push (cons (format "%s (%s)"
                                   (jetpacs-sections--menu-label binding) key)
                           key)
                     cands))))))
     km))
  cands)

(defun jetpacs-sections--menu-candidates (pos)
  "The section menu at POS: an alist of (LABEL . KEY-STRING).

Reads the region's own text-property keymap FIRST and the major mode's
map second, nearest-wins.  The mode map is where magit actually puts its
verbs — `s' stage, `u' unstage, `c' commit are mode-level, not
per-section — so reading only text-property maps left almost every
section offering nothing but the fold toggle, and the substrate's promise
of \"that section's own key bindings\" unmet.

Key description strings are what get replayed; commands are resolved by
the buffer's own keymaps at dispatch time, and re-derived from THIS
function before anything runs (SPEC 23.2), so what is offerable here is
exactly what is replayable."
  (let ((cands (jetpacs-sections--map-candidates
                (or (get-char-property pos 'keymap)
                    (get-char-property pos 'local-map))
                nil)))
    (setq cands (jetpacs-sections--map-candidates
                 (current-local-map) cands jetpacs-sections-menu-mode-keys))
    (let ((all (nreverse (cons (cons "Toggle fold (TAB)" "TAB") cands))))
      (if (<= (length all) jetpacs-sections-menu-max)
          all
        (seq-take all jetpacs-sections-menu-max)))))

(defun jetpacs-sections--replay-key (buf pos key params)
  "Replay KEY at POS in BUF, then re-push.  Runs from a continuation.

KEY arrives OVER THE WIRE (the dialog\'s submitted value), so SPEC 23.2 —
\"MUST NOT pass unvalidated action or command names to an ambient command
dispatcher\" — applies with full force: a bare `(execute-kbd-macro (kbd
KEY))' would let a Companion send magit\'s `x' (reset), `C-x C-f', or
`M-x'.  The poc was safe only incidentally, because its choice came from
a LOCAL `completing-read' and never from the wire.

KEY is therefore re-validated at replay time against the candidates
derived FRESH at POS, and the binding it resolves to is re-checked for
`commandp' and against the denylist.  Nothing outside that section\'s own
current keymap can be reached."
  (with-current-buffer buf
    (goto-char (min (max (point-min) (truncate pos)) (point-max)))
    (let* ((cands (jetpacs-sections--menu-candidates (point)))
           (member (rassoc key cands))
           (binding (and member (key-binding (kbd key) t))))
      (cond
       ((null member)
        (message "jetpacs-sections: refused %S — not a candidate at this \
section (SPEC 23.2)" key))
       ((not (and (jetpacs-command-visible-p binding)
                  (not (memq binding jetpacs-sections-menu-denylist))))
        (message "jetpacs-sections: refused %S — resolves to no offerable \
command" key))
       (t
        ;; Run the COMMAND the gate above validated, not the key.
        ;; `execute-kbd-macro' spins a command loop against the SELECTED
        ;; WINDOW's buffer, and on the device this buffer is in no window
        ;; — so the offered verb never ran and the key self-inserted
        ;; somewhere else.  Worse here than in the palette: the gate
        ;; resolves the binding with BUF current, while the replay
        ;; re-resolved it against a different buffer, so the command the
        ;; denylist cleared and the command that ran were two separate
        ;; lookups.  A destructive-magit entry could therefore be refused
        ;; on inspection and reached in fact.  One lookup, one command,
        ;; run under the nav shims with BUF current.
        (jetpacs-buffer-call-shimmed
         binding
         (lambda (err)
           (message "jetpacs-sections: %s failed: %s"
                    key (jetpacs--error-label err))))))))
  (jetpacs-sections--refresh params))

(defvar jetpacs-sections--dialog-seq 0
  "Monotonic counter making each `sections.menu' dialog id fresh.")

(defun jetpacs-sections--dialog-id (buf pos)
  "A FRESH SPEC 18.1 dialog id for the menu at POS in BUF.
Deriving the id from (buffer, pos) alone made it deterministic, so a
second long-press on the same header while the first dialog was still
outstanding reused the id — and 18.1 says a second outstanding request
with the same `dialog_id' MUST receive `1201 content-invalid'.  Which is
exactly what an impatient double-press does."
  (format "sections-%s-%d"
          (abs (sxhash (list (buffer-name buf) pos)))
          (cl-incf jetpacs-sections--dialog-seq)))

(defun jetpacs-sections--show-menu (buf pos params)
  "Offer the section menu at POS in BUF as an EBP dialog.
`completing-read' is NOT an option here: the poc called it inside the
handler, which under this architecture blocks the jsonrpc dispatch extent
\(decision D2) — the Companion would never learn the outcome and, on a
headless daemon, nothing would ever answer.  The dialog is the
conformant equivalent: SPEC 18.1, asynchronous, with the choice arriving
in a callback."
  (let* ((client (jetpacs-client))
         (cands (with-current-buffer buf
                  (save-excursion
                    (goto-char (min (max (point-min) (truncate pos))
                                    (point-max)))
                    (jetpacs-sections--menu-candidates (point))))))
    (when (and client cands)
      (ebp-client-dialog-show
       client
       (jetpacs-sections--dialog-id buf pos)
       (apply #'jetpacs-column
              (jetpacs-text "Section action" :style "title")
              (append
               (mapcar (lambda (c)
                         (jetpacs-button (car c)
                                         (jetpacs-dialog-submit :value (cdr c))))
                       cands)
               ;; SPEC 18.1 gives the platform its own dismissal, but a
               ;; picker that offers no way out reads as a trap — and on a
               ;; device whose back gesture is ambiguous inside a dialog,
               ;; it can be one.
               (list (jetpacs-button "Cancel" (jetpacs-dialog-dismiss)))))
       :callback
       (lambda (status result _error)
         (when (and (equal status "submitted") (stringp (plist-get result :value)))
           (jetpacs-sections--replay-key buf pos (plist-get result :value)
                                         params)))))))

(jetpacs-defaction "sections.menu"
  (lambda (args params)
    (let* ((name (plist-get args :buffer))
           (pos (plist-get args :pos))
           (buf (jetpacs-sections--section-buffer name)))
      (cond
       ;; `integerp', not `numberp': a float clears the type gate and
       ;; then misses `jetpacs-buffer-exposed-p''s `eql' hash, so it
       ;; would be refused for the wrong reason.
       ((not (and buf (integerp pos))) 'rejected)
       ((jetpacs-event-stale-p params) 'stale)
       ((not (jetpacs-buffer-exposed-p name pos "sections.menu")) 'rejected)
       ;; The dialog needs the capability; without it there is no
       ;; non-blocking way to ask, so say so rather than hang.
       ((not (jetpacs-granted-p "surfaces.dialog")) 'rejected)
       (t
        ;; The dialog itself is a request; issuing it from a continuation
        ;; keeps this handler's reply prompt (D2).
        (run-at-time 0 nil
                     (lambda () (jetpacs-sections--show-menu buf pos params)))
        'accepted)))))

;; The library is third-party: register only once it exists.  The base mode
;; covers magit, forge, kubernetes.el, taxy-magit-section.
(with-eval-after-load 'magit-section
  (jetpacs-render-buffer-register 'magit-section-mode #'jetpacs-sections-render))

(provide 'jetpacs-sections)
;;; jetpacs-sections.el ends here
