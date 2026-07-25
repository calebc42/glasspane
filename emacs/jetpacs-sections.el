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
;; folding is instant and client-side, no round trip — with Emacs's own
;; fold state mirrored at render time, and a long-press on any header
;; offering that section's OWN key bindings, so the phone gets magit's
;; per-section verbs without one command name ever crossing the wire (the
;; wire carries keys and positions; the buffer's keymaps decide meaning).
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
(require 'jetpacs-buffer)       ; line spans, dispatch registry, exposure
(require 'jetpacs-results)      ; the region-view seam + RET resolution

;; The magit-section library, never required from core:
(declare-function magit-section-ident "ext:magit-section" (section))
(defvar magit-root-section)

;; --- Configuration -----------------------------------------------------------

(defcustom jetpacs-sections-max-lines 500
  "Total body-line budget for one rendered section buffer.
Past the budget, remaining sections still render their headers (the tree
stays navigable) but bodies are elided with a note."
  :type 'integer :group 'jetpacs)

(defconst jetpacs-sections--menu-denylist
  '(self-insert-command digit-argument negative-argument universal-argument
    undefined ignore keyboard-quit keyboard-escape-quit
    mouse-drag-region mouse-set-point mouse-set-region
    magit-mouse-toggle-section)
  "Commands never offered in the section context menu.")

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
  "Whether SEC is folded in Emacs."
  (jetpacs-sections--slot sec 'hidden))

(defun jetpacs-sections--id (sec)
  "A stable collapsible id for SEC: its ident path, hashed.
`magit-section-ident' is the library's own stable identity (it survives a
refresh, which keeps client-side fold state attached to the same
section).  Falls back to the start position."
  (or (condition-case nil
          (md5 (format "%S" (magit-section-ident sec)))
        (error nil))
      (format "sec-%s" (jetpacs-sections--pos sec 'start))))

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
           (when (numberp pos)
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
  "SPANS as a `rich_text' node, or a Core `text' when unadvertised (16.2)."
  (if (jetpacs-node-advertised-p "rich_text")
      (jetpacs-rich-text spans)
    (jetpacs-text (mapconcat (lambda (s) (or (plist-get s :text) "")) spans "")
                  :style "mono")))

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
            (push (jetpacs-text
                   (format "… %d more line(s) in Emacs"
                           (count-lines (point) end))
                   :style "caption")
                  nodes)
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
  "A collapsible card for SEC, or a Core fallback when unadvertised (16.2).
Exposes START under `sections.menu' for the long-press."
  (jetpacs-buffer-expose name start "sections.menu")
  (let ((menu (jetpacs-action "sections.menu"
                              :args (list :buffer name :pos start))))
    (if (jetpacs-node-advertised-p "collapsible")
        (apply #'jetpacs-collapsible
               (jetpacs-sections--id sec) header
               (append children
                       (list :collapsed (if (jetpacs-sections--hidden-p sec)
                                            t :json-false)
                             :on-long-tap menu)))
      ;; Core: header, then the children inline — folding is the
      ;; Companion's affordance and there is no Core equivalent, so the
      ;; content simply shows.
      (apply #'jetpacs-column header children))))

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
     ((null end)
      (list (jetpacs-sections--rich
             (list (jetpacs-span "… section still loading" :mono t)))))
     ;; Heading + revealed content -> a collapsible card.
     ((and content (< content end))
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
    (let ((root (jetpacs-sections--root)))
      (if (or (null root) (< (buffer-size) 1))
          (jetpacs-buffer-render buf)
        ;; The scanner must see the whole tree, including bodies Emacs has
        ;; folded away (`hidden' mirrors into :collapsed instead) — an
        ;; invisibility spec of nil makes `invisible' props inert for the
        ;; walk without touching buffer state.
        (let ((buffer-invisibility-spec nil)
              (budget (cons jetpacs-sections-max-lines nil))
              (name (buffer-name buf)))
          ;; This render supersedes the last one's tap targets.
          (jetpacs-buffer-forget-exposed name)
          ;; The tree is third-party eieio read through `slot-value': an
          ;; unbound slot, a missing slot on an exotic section class, or a
          ;; mid-refresh nil marker must cost this SKIN, never the push.
          (or (condition-case err
                  (jetpacs-sections--emit root name budget)
                (error
                 (message "jetpacs-sections: tree walk failed (%s); \
falling back to Tier 0" (jetpacs--error-label err))
                 nil))
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
Runs the region's own RET command under `jetpacs-buffer-call-shimmed'; a
command that leaves the buffer shows its destination in the region view
and returns non-nil, one that acts in place returns nil.  SIGNALS when
the command itself failed.

The ON-ERROR thunk is load-bearing.  `jetpacs-buffer-call-shimmed'
swallows the error and still returns `(current-buffer) . (point)', so a
command that blew up is indistinguishable from one that acted in place —
and the handler would answer `accepted' for a visit that never happened.
That got sharper with the Phase A prompt ban: a command reaching
`find-file-noselect' (large-file confirm, unsafe locals, TRAMP auth) now
SIGNALS `inhibited-interaction' instead of hanging, and swallowing it
would turn a wedge into a silent lie."
  (with-current-buffer buf
    (goto-char (min (max (point-min) (truncate pos)) (point-max)))
    (let ((cmd (jetpacs-results--visit-command (point))))
      (when (commandp cmd)
        (let* ((failed nil)
               (dest (jetpacs-buffer-call-shimmed
                      cmd (lambda (err) (setq failed err))))
               (dest-buf (car dest)))
          (when failed (signal (car failed) (cdr failed)))
          (when (and dest-buf (not (eq dest-buf buf)))
            (pcase-let ((`(,beg ,end ,label ,point)
                         (jetpacs-results--region-around dest-buf (cdr dest))))
              (funcall jetpacs-results-visit-region-function
                       (buffer-name dest-buf) beg end label point))
            t))))))

(jetpacs-defaction "sections.visit"
  ;; BUFFER must be a live magit-section buffer, POS a row this render
  ;; actually offered.  Follow if the row's command jumps; re-push if it
  ;; acted in place (stage, toggle) or could not follow.
  (lambda (args params)
    (let* ((name (plist-get args :buffer))
           (pos (plist-get args :pos))
           (buf (jetpacs-sections--section-buffer name))
           (jetpacs-results--event-surface (plist-get params :surface)))
      (cond
       ((not (and buf (numberp pos))) 'rejected)
       ((not (jetpacs-buffer-exposed-p name pos "sections.visit")) 'rejected)
       ((jetpacs-event-stale-p params) 'stale)
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

(defun jetpacs-sections--menu-candidates (pos)
  "The section menu at POS: an alist of (LABEL . KEY-STRING).
Single keys from the region's own keymap (the section's verbs), plus the
fold toggle.  Key description strings are what get replayed — commands
are resolved by the buffer's own keymaps at dispatch time."
  (let ((km (or (get-char-property pos 'keymap)
                (get-char-property pos 'local-map)))
        cands)
    (when (keymapp km)
      (map-keymap
       (lambda (event binding)
         (when (and (commandp binding)
                    (not (memq binding jetpacs-sections--menu-denylist))
                    (or (and (integerp event) (< 31 event 127))
                        (memq event '(return tab))))
           (let ((key (key-description (vector event))))
             (push (cons (format "%s (%s)"
                                 (jetpacs-sections--menu-label binding) key)
                         key)
                   cands))))
       km))
    (nreverse (cons (cons "Toggle fold (TAB)" "TAB") cands))))

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
       ((not (and (commandp binding)
                  (not (memq binding jetpacs-sections--menu-denylist))))
        (message "jetpacs-sections: refused %S — resolves to no offerable \
command" key))
       (t
        (condition-case err
            (let ((last-input-event nil)
                  (last-nonmenu-event nil))
              ;; The KEY (not the command) is replayed, so magit prefixes
              ;; and transients behave as they do under the user\'s hands.
              (execute-kbd-macro (kbd key)))
          (error (message "jetpacs-sections: %s failed: %s"
                          key (jetpacs--error-label err))))))))
  (jetpacs-sections--refresh params))

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
       (format "sections-%s" (abs (sxhash (list (buffer-name buf) pos))))
       (apply #'jetpacs-column
              (jetpacs-text "Section action" :style "title")
              (mapcar (lambda (c)
                        (jetpacs-button (car c)
                                        (jetpacs-dialog-submit :value (cdr c))))
                      cands))
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
       ((not (and buf (numberp pos))) 'rejected)
       ((not (jetpacs-buffer-exposed-p name pos "sections.menu")) 'rejected)
       ;; The dialog needs the capability; without it there is no
       ;; non-blocking way to ask, so say so rather than hang.
       ((not (and (jetpacs-client)
                  (seq-contains-p (ebp-client-granted (jetpacs-client))
                                  "surfaces.dialog")))
        'rejected)
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
