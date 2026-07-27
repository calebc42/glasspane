;;; jetpacs-keymap.el --- Keymap extraction and menu-bar mining -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The command palette's two data sources, ported from poc-v1 (JA-3b):
;;
;;   - BINDING EXTRACTION: walk a buffer's active keymaps (minor > local
;;     > global) into (KEY-DESC COMMAND SOURCE) rows, deduped by key
;;     description so a nearer map's meaning wins.
;;   - MENU-BAR MINING: flatten the same maps' [menu-bar] keymaps into
;;     breadcrumbed (\"File ▸ Save As…\") command leaves.  This is the
;;     highest-leverage idea in the app tier: menu items carry
;;     HUMAN-WRITTEN labels and :help strings for an arbitrary mode's
;;     commands, so any installed package becomes touch-usable without
;;     anyone writing a skin for it.
;;
;; This module is a PURE LIBRARY: no owner, no surface, no actions, no
;; wire contact.  `jetpacs-emacs-ui' hosts the palette UI and registers
;; the actions that call in here.  The poc's pie-menu registry (~217
;; lines) is deliberately unported per decision D-9 — the SPEC 18.3
;; wire plumbing stays (ebp-client-pie-menu-show), the Emacs-side
;; registry belongs to a future Tier-1 — and its transient walkers
;; retire in favor of jetpacs-transient.el's reader at its own rung.
;;
;; Two poc bugs are fixed rather than ported (do not "restore" them
;; from the source):
;;   1. `--extract-bindings' destructured `current-minor-mode-maps' as
;;      (VAR . MAP) conses; it returns plain KEYMAPS, so every
;;      minor-mode binding was silently dropped.  (The menu miner got
;;      this right; the extractor never did.)
;;   2. `--walk-keymap' accumulated recursion results with
;;      (setq bindings (append bindings …)) — quadratic; now an
;;      accumulator closure like the menu walker always used.
;;
;; Filtering is layered per the JA-3a consolidation: the global
;; noise/suppression answer is `jetpacs-command-visible-p' (which the
;; user extends via `jetpacs-suppressed-commands' or the
;; `jetpacs-unsupported' property); `jetpacs-keymap-denylist' keeps
;; only PALETTE-LOCAL noise — navigation and undo, pointless as
;; palette entries yet legitimate M-x targets, so putting them in the
;; global list would wrongly make them unrunnable from the device
;; picker (it completes with require-match).

;;; Code:

(require 'cl-lib)
(require 'jetpacs-commands)

(defcustom jetpacs-keymap-show-global nil
  "When non-nil, include global-map bindings and menus in the palette.
Usually these are ambient (C-x C-s, C-g, the File/Edit menus) and not
useful on a phone; the mode-specific bindings are what matter."
  :type 'boolean :group 'jetpacs)

(defcustom jetpacs-keymap-max-bindings 200
  "Maximum number of bindings to extract from a buffer's keymaps.
Safety cap so a mode with hundreds of bindings doesn't produce an
unbounded candidate list."
  :type 'natnum :group 'jetpacs)

(defcustom jetpacs-keymap-menu-max-items 150
  "Cap on menu-derived palette entries mined from a buffer's menus."
  :type 'natnum :group 'jetpacs)

(defcustom jetpacs-keymap-denylist
  '(;; Minibuffer plumbing — meaningless outside a minibuffer.
    abort-recursive-edit abort-minibuffers
    exit-minibuffer minibuffer-keyboard-quit
    ;; Insertion — a palette runs commands, it doesn't type.
    newline newline-and-indent open-line
    ;; Navigation/undo: fine from M-x, noise as palette rows — a phone
    ;; scrolls by touch, and `undo' belongs on chrome, not in a list.
    undo undo-redo
    forward-char backward-char
    next-line previous-line
    scroll-up-command scroll-down-command
    beginning-of-buffer end-of-buffer
    move-beginning-of-line move-end-of-line)
  "Commands excluded from the command palette, IN ADDITION to
`jetpacs-suppressed-commands' (consulted via
`jetpacs-command-visible-p').  Entries here remain reachable from the
device M-x; the global list is for commands that should not be
offered anywhere."
  :type '(repeat symbol) :group 'jetpacs)

(defun jetpacs-keymap--offerable-p (cmd)
  "Non-nil when CMD belongs in the palette."
  (and (jetpacs-command-visible-p cmd)
       (not (memq cmd jetpacs-keymap-denylist))))

;; --- Binding extraction ------------------------------------------------------

(defun jetpacs-keymap--key-printable-p (key)
  "Non-nil if KEY (a key vector) represents a printable/keyboard binding.
Excludes mouse events, menu-bar, tool-bar, header-line, mode-line, and
cons event types."
  (let ((first (aref key 0)))
    (not (or (and (symbolp first)
                  (let ((name (symbol-name first)))
                    (or (string-prefix-p "mouse-" name)
                        (string-prefix-p "drag-mouse-" name)
                        (string-prefix-p "double-mouse-" name)
                        (string-prefix-p "triple-mouse-" name)
                        (string-prefix-p "down-mouse-" name)
                        (string-prefix-p "wheel-" name)
                        (string-match-p "\\`\\(menu-bar\\|tool-bar\\|header-line\\|mode-line\\|tab-bar\\|tab-line\\|vertical-scroll-bar\\|horizontal-scroll-bar\\)" name))))
            ;; Event types that are conses (e.g. (menu-bar ...)).
            (consp first)))))

(defun jetpacs-keymap--walk-keymap (keymap prefix-keys)
  "Walk KEYMAP and return a list of (KEY-VEC . COMMAND) pairs.
PREFIX-KEYS is a key vector prepended to each binding (for recursive
descent into prefix keymaps).  Leaf (commandp) bindings carry their
command; a key the map CLAIMS without offering a command — an explicit
unbind, or a prefix keymap — is emitted as (KEY-VEC . nil), a claim
sentinel.

The sentinels are load-bearing, not bookkeeping.  `map-keymap' walks a
map's PARENT as well, child entries first, so a mode that shadows an
inherited binding with an explicit nil (`diff-mode' nils out
\\`M-q'/\\`M-r'/\\`M-A'/\\`M-R'/\\`M-W'/\\`M-g' precisely to let the global
\\`M-<foo>' bindings through) hands us the nil AND then the parent's
real command for the same event.  Dropping the nil silently — what this
did before — resurrected the parent binding under a key Emacs resolves
elsewhere, and the palette then labelled a row \\='M-q · quit-window\\='
that ran `fill-paragraph', reflowing and destroying a patch buffer.
First definition per event wins, at each level, which is how Emacs
itself resolves the key."
  (let (out)
    (cl-labels
        ((walk (km prefix)
           (when (keymapp km)
             ;; Per-LEVEL claim set: `map-keymap' yields this map's own
             ;; entries before its parent's, so first-wins here is
             ;; exactly the shadowing rule.
             (let ((claimed (make-hash-table :test #'eql)))
               (map-keymap
                (lambda (event def)
                  (unless (gethash event claimed)
                    (puthash event t claimed)
                    (let* ((key-vec (vconcat prefix (vector event)))
                           ;; Unwrap menu-item forms to the real definition.
                           (def (if (and (consp def) (eq (car def) 'menu-item))
                                    (nth 2 def)
                                  def))
                           ;; Resolve for the keymapp test only; STORE the
                           ;; original symbol so symbol-name works downstream.
                           (resolved (if (and (symbolp def) (fboundp def))
                                         (indirect-function def)
                                       def)))
                      (cond
                       ((not (jetpacs-keymap--key-printable-p key-vec)) nil)
                       ((and (keymapp resolved) (< (length key-vec) 4))
                        ;; A prefix map claims the bare key too: nothing
                        ;; farther may offer a command under it.
                        (push (cons key-vec nil) out)
                        (walk resolved key-vec))
                       ((commandp def)
                        (push (cons key-vec def) out))
                       ;; An explicit unbind, or anything else this map
                       ;; defines that we will not offer: CLAIM the key.
                       (t (push (cons key-vec nil) out))))))
                km)))))
      (walk keymap prefix-keys))
    (nreverse out)))

(defun jetpacs-keymap-extract-bindings (buffer)
  "Extract printable key->command bindings from BUFFER's active keymaps.
Returns a list of (KEY-DESC COMMAND SOURCE) where KEY-DESC is a string
like \"s\" or \"C-c C-t\", COMMAND is a symbol, and SOURCE is `minor',
the major mode symbol, or `global'.  Priority order minor > local >
global: the first writer of a key description wins, which is also how
Emacs resolves the key."
  (with-current-buffer buffer
    (let ((seen (make-hash-table :test 'equal))
          (count 0)
          result)
      (cl-flet ((collect (keymap source)
                  (when (and keymap (< count jetpacs-keymap-max-bindings))
                    (dolist (pair (jetpacs-keymap--walk-keymap keymap []))
                      (when (< count jetpacs-keymap-max-bindings)
                        (let* ((key-vec (car pair))
                               (cmd (cdr pair))
                               (desc (key-description key-vec)))
                          (unless (gethash desc seen)
                            ;; CLAIM the key before deciding whether to
                            ;; offer it.  A nearer map that binds a key
                            ;; must block a farther map's row for that
                            ;; key even when we offer nothing ourselves —
                            ;; an explicit unbind, a prefix map, or a
                            ;; command the palette filters out.  Claiming
                            ;; only on acceptance is what let a farther
                            ;; command be offered under a shadowed key.
                            (puthash desc t seen)
                            (when (and cmd
                                       (jetpacs-keymap--offerable-p cmd)
                                       (not (string-prefix-p "menu-bar" desc))
                                       (not (string-prefix-p "<" desc))
                                       ;; The invariant, enforced rather
                                       ;; than assumed: a row may only
                                       ;; claim a key that really runs
                                       ;; its command in THIS buffer.
                                       (eq cmd (key-binding key-vec)))
                              (push (list desc cmd source) result)
                              (setq count (1+ count))))))))))
        ;; `current-minor-mode-maps' returns plain KEYMAPS (poc bug #1
        ;; destructured them as (VAR . MAP) and extracted nothing).
        (dolist (km (current-minor-mode-maps))
          (collect km 'minor))
        (collect (current-local-map) major-mode)
        (when jetpacs-keymap-show-global
          (collect (current-global-map) 'global)))
      (nreverse result))))

(defun jetpacs-keymap-command-label (cmd)
  "Human-readable label for command CMD.
Strips only the current buffer's major-mode stem (so `org-agenda-list'
becomes \"agenda-list\" in an org buffer but keeps its full name
elsewhere).  For a hyphenated mode like `magit-status-mode', the first
segment (\"magit-\") is also tried.  Never strips blindly: a greedy
last-dash strip would turn `forward-paragraph' into \"paragraph\".
Reads the dynamic `major-mode' — call with the target buffer current."
  (if (not (symbolp cmd))
      (format "%s" cmd)
    (let* ((name (symbol-name cmd))
           (stem (string-remove-suffix "-mode" (symbol-name major-mode)))
           (head (car (split-string stem "-"))))
      (cond
       ((and (string-prefix-p (concat stem "-") name)
             (> (length name) (1+ (length stem))))
        (substring name (1+ (length stem))))
       ((and (string-prefix-p (concat head "-") name)
             (> (length name) (1+ (length head))))
        (substring name (1+ (length head))))
       (t name)))))

;; --- Menu-bar mining ---------------------------------------------------------

(defun jetpacs-keymap--menu-pred (props key)
  "Non-nil when PROPS' KEY predicate (`:enable'/`:visible') passes or is absent.
A predicate that signals is treated as passing — better to offer a
command that turns out disabled than to hide one on a spurious error.
The `eval' here runs IN-PROCESS menu-item forms authored by installed
packages, never wire data, so SPEC 23.2 is not implicated; predicates
are contextual (mark active, region live), which is why candidates are
recomputed per palette open rather than cached."
  (let ((m (plist-member props key)))
    (or (not m)
        (condition-case nil (eval (plist-get props key) t) (error t)))))

(defun jetpacs-keymap--menu-item-parse (binding)
  "Parse a menu keymap BINDING into (LABEL REAL HELP), or nil.
Handles the `menu-item' form and the older (STRING . REAL) /
\(STRING HELP . REAL) forms; applies `:filter' and drops items whose
`:enable'/`:visible' predicate is nil, and separators.  easy-menu
compiles to `menu-item' forms, so both authoring styles are covered."
  (cond
   ((and (consp binding) (eq (car binding) 'menu-item))
    (let* ((label (nth 1 binding))
           (real (nth 2 binding))
           (props (nthcdr 3 binding))
           (filter (plist-get props :filter)))
      (when (functionp filter)
        (setq real (ignore-errors (funcall filter real))))
      (when (and (stringp label)
                 (not (string-prefix-p "--" label)) ; separator
                 (jetpacs-keymap--menu-pred props :enable)
                 (jetpacs-keymap--menu-pred props :visible))
        (list label real (plist-get props :help)))))
   ((and (consp binding) (stringp (car binding)))
    (let ((label (car binding))
          (rest (cdr binding)))
      (unless (string-prefix-p "--" label)
        (if (and (consp rest) (stringp (car rest)))
            (list label (cdr rest) (car rest))   ; (STRING HELP . REAL)
          (list label rest nil)))))              ; (STRING . REAL)
   (t nil)))

(defun jetpacs-keymap--menu-entries (keymap)
  "Flatten menu-bar KEYMAP into (LABEL-PATH HELP COMMAND) leaves.
Submenus recurse with a breadcrumb label path (\"File ▸ Save As…\");
disabled/invisible items, separators, and non-command leaves are
dropped.  Depth-capped at 5 and item-capped at
`jetpacs-keymap-menu-max-items'."
  (let (out)
    (cl-labels
        ((walk (km crumb depth)
           (when (and (keymapp km) (< depth 5)
                      (< (length out) jetpacs-keymap-menu-max-items))
             (map-keymap
              (lambda (_event binding)
                (when (< (length out) jetpacs-keymap-menu-max-items)
                  (when-let* ((parsed (jetpacs-keymap--menu-item-parse binding)))
                    (let* ((label (nth 0 parsed))
                           (real (nth 1 parsed))
                           (help (nth 2 parsed))
                           (path (if crumb (concat crumb " ▸ " label) label)))
                      (cond
                       ((keymapp real) (walk real path (1+ depth)))
                       ((commandp real) (push (list path help real) out)))))))
              km))))
      (walk keymap nil 0))
    (nreverse out)))

(defun jetpacs-keymap--menu-maps (buf)
  "Menu-bar keymaps to mine for BUF: minor-mode and local (plus global
when `jetpacs-keymap-show-global').  The global menu is skipped by
default — its File/Edit/… entries are generic noise next to the mode's
own menu."
  (with-current-buffer buf
    (let (maps)
      (dolist (km (current-minor-mode-maps))
        (let ((menu (and (keymapp km) (lookup-key km [menu-bar]))))
          (when (keymapp menu) (push menu maps))))
      (when-let* ((lm (current-local-map))
                  (menu (lookup-key lm [menu-bar])))
        (when (keymapp menu) (push menu maps)))
      (when jetpacs-keymap-show-global
        (let ((menu (lookup-key (current-global-map) [menu-bar])))
          (when (keymapp menu) (push menu maps))))
      (nreverse maps))))

(defun jetpacs-keymap-menu-candidates (buf)
  "Palette candidates mined from BUF's menu-bar keymaps.
Returns an alist of (DISPLAY . (command . SYMBOL)), deduped by command;
DISPLAY is the breadcrumb path, with the first :help line appended when
one exists."
  (let (result (seen (make-hash-table :test 'eq)))
    (dolist (menu (jetpacs-keymap--menu-maps buf))
      (dolist (entry (jetpacs-keymap--menu-entries menu))
        (let* ((path (nth 0 entry))
               (help (nth 1 entry))
               (cmd (nth 2 entry))
               (display (if (and (stringp help) (not (string-empty-p help)))
                            (format "%s — %s" path
                                    (car (split-string help "\n" t)))
                          path)))
          (unless (or (gethash cmd seen)
                      (not (jetpacs-keymap--offerable-p cmd)))
            (puthash cmd t seen)
            (push (cons display (cons 'command cmd)) result)))))
    (nreverse result)))

;; --- The palette candidate list ----------------------------------------------

(defun jetpacs-keymap-palette-candidates (buf)
  "Alist of (DISPLAY . TARGET) for BUF's key bindings and menu items.
TARGET is (key COMMAND . KEY-DESC) for a keybinding or (command . SYMBOL)
for a menu-derived entry.  Keybindings come first (they carry the
shortcut), then the human-labeled menu entries.  Recomputed per call BY
DESIGN: menu :enable/:visible/:filter predicates are contextual, and at
the extraction caps this costs milliseconds.

A key row carries the COMMAND, not just its key description, and the
key survives only as display sugar.  Executing the command we LABELLED
makes label and effect identical by construction; re-resolving the
description at tap time — what this did before — reintroduces every way
the two can diverge, including char-property keymaps that extraction
never walked and any binding that changed between render and tap."
  (with-current-buffer buf
    (append
     (mapcar (lambda (b)
               (pcase-let ((`(,key ,cmd ,_source) b))
                 (cons (format "%s  ·  %s" key
                               (jetpacs-keymap-command-label cmd))
                       (cons 'key (cons cmd key)))))
             (jetpacs-keymap-extract-bindings buf))
     (jetpacs-keymap-menu-candidates buf))))

(provide 'jetpacs-keymap)
;;; jetpacs-keymap.el ends here
