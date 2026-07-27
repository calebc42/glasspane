;;; jetpacs-commands.el --- Command visibility on device surfaces -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The shared vocabulary for which Emacs commands the device should
;; OFFER.  Plenty of commands are perfectly runnable but nonsensical
;; from a phone — they need mouse/wheel events the bridge never sends,
;; or they suspend the host session — and every candidate-producing
;; surface (the M-x picker, the command palette, the sections
;; long-press menu) needs the same answer to "should this command be
;; suggested here?".  This module is that answer, in three layers:
;;
;;   1. `jetpacs-suppressed-commands' — a defcustom of symbols and
;;      regexps, the user's block list.
;;   2. The `jetpacs-unsupported' symbol property — the definition-site
;;      channel, so an app or skin can mark its own commands as
;;      not-for-mobile without editing the user's list:
;;        (put 'my-desktop-only-cmd 'jetpacs-unsupported t)
;;   3. `jetpacs-command-visible-p' — the predicate combining both over
;;      a `commandp' baseline; consumers pass it wherever a command
;;      predicate goes (the M-x action hands it to `completing-read').
;;
;; Ported from poc-v1 (JA-3a); this module is also the CONSOLIDATION
;; point the plan names: the sections menu and the keymap palette each
;; hand-rolled a noise denylist, and their overlap (self-insert,
;; argument plumbing, quit commands) now lives in this module's
;; defaults.  What does NOT consolidate is deliberate:
;;
;;   - `jetpacs-sections-menu-denylist' keeps its destructive-magit
;;     half — that is a no-confirm-affordance SAFETY list, not mobile
;;     noise.  `magit-discard' is rightly suppressed from a long-press
;;     menu yet fine from a require-match M-x where the user typed it
;;     in full.
;;   - `jetpacs-keymap-denylist' keeps navigation noise (forward-char,
;;     undo, scroll…) — pointless as PALETTE entries but legitimate
;;     M-x targets; putting them here would make them unrunnable from
;;     the device entirely (the picker completes with require-match).
;;
;; Altitude note: this is UX-level filtering of SUGGESTIONS, not a
;; security boundary — the dispatch boundary remains the SPEC 14.1
;; action allowlist.  Nothing here touches the wire: candidates are
;; filtered before they are ever shipped.

;;; Code:

(require 'jetpacs-surfaces)
(require 'seq)

(defcustom jetpacs-suppressed-commands
  '(suspend-frame
    suspend-emacs
    mwheel-scroll
    self-insert-command
    digit-argument
    negative-argument
    universal-argument
    undefined
    ignore
    keyboard-quit
    keyboard-escape-quit
    "\\`mouse-"
    "\\`scroll-bar-"
    "\\`tmm-")
  "Commands hidden from every device command surface.
Each entry is either a symbol (matched with `eq') or a string (a
regexp matched against the command name with `string-match-p' —
anchor with \\\\=` when you mean a prefix).  The defaults are commands
that cannot work over the bridge (they require mouse or wheel events
the device never sends, or suspend the host Emacs out from under the
session) plus the key-plumbing commands every keymap carries
\(`self-insert-command', the argument readers, the quit commands) that
are noise on any device surface and pointless from a picker.

Suppression is silent and, because the M-x picker completes with
require-match, total for that surface: a suppressed command cannot be
run from it even when typed in full.  To suppress a command from its
definition site instead (an app shipping desktop-only commands), set
the `jetpacs-unsupported' symbol property rather than editing this
list."
  :type '(repeat (choice (symbol :tag "Command")
                         (regexp :tag "Name regexp")))
  :group 'jetpacs)

(defun jetpacs-command-visible-p (symbol)
  "Non-nil when SYMBOL should be offered as a command on the device.
True when SYMBOL is a command (`commandp'), does not carry a non-nil
`jetpacs-unsupported' symbol property, and matches no entry of
`jetpacs-suppressed-commands'.  Designed as a `completing-read'
PREDICATE over `obarray' (the device M-x), and as the visibility
test for any other surface that suggests commands."
  (and (commandp symbol)
       (not (get symbol 'jetpacs-unsupported))
       (let ((name (symbol-name symbol)))
         (not (seq-some (lambda (entry)
                          (if (stringp entry)
                              (string-match-p entry name)
                            (eq entry symbol)))
                        jetpacs-suppressed-commands)))))

(provide 'jetpacs-commands)
;;; jetpacs-commands.el ends here
