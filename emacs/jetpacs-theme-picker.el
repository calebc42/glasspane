;;; jetpacs-theme-picker.el --- shared scaffold for theme control screens -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The generic half of a theme picker/control satellite screen: palette
;; strip and per-theme preview swatches, prefix-stripped display names,
;; the companion-mirror note, the current-theme header card, the
;; light/dark grouped picker, and the customize cross-link.  A concrete
;; screen supplies its provider functions (theme list, current, dark-p,
;; palette color) and its action names; glasspane-ef is the first
;; instantiation, for Prot's ef-themes — and it STAYS app-side, because
;; ef-themes is in the app's package set, not the foundation's.
;;
;; Foundation module by the ratified §3 step-3 promotion
;; (docs/PLAN-jetpacs-debt-and-scaffold.md), REVERSING the
;; FOUNDATION-GAPS #8 ruling (docs/PLAN-glasspane-app.md) that had
;; landed the G8 port app-local as glasspane-theme-picker.el pending a
;; second consumer.  The reversal costs nothing because the closure was
;; foundation-only from the day it landed — cl-lib, jetpacs-widgets,
;; jetpacs-theme, zero glasspane symbols — so under the 2026-08-06
;; naming rule (a prefix is a claim about the require closure) the old
;; prefix overclaimed, and the rename IS the whole promotion.
;;
;; G8 port of v1 core jetpacs-theme-picker.el.  Rewrites against v1:
;;  - `jetpacs-swatch' has no v3 node helper: the chip is a shaped
;;    `jetpacs-surface' sized through `jetpacs-with-attrs' (width and
;;    height are universal attributes, not surface members).
;;  - The mirror note reads `jetpacs-theme-mode' `mirror', not v1's
;;    `emacs' (T2); jetpacs-theme is a hard require, so v1's boundp
;;    probe on the mode variable is gone.
;;  - Action `:args' are member plists (T3); positional text styles are
;;    `:style' strings (T5).
;;
;; Per-theme previews gate on `modus-themes-activate' — the modus 5.0
;; palette machinery that resolving a NON-current theme's colors needs;
;; derivative families built on that API (ef-themes 2.0+) get previews
;; for free, and older providers degrade to clean name-only rows.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-theme)

(defconst jetpacs-theme-picker-strip-keys
  '(bg-main fg-main accent-0 accent-1 accent-2 accent-3 err info)
  "Palette roles shown in the current theme's swatch strip.")

(defun jetpacs-theme-picker--swatch (hex &optional size)
  "A round color chip of HEX at SIZE dp (default 22), or nil when HEX is nil."
  (when hex
    (jetpacs-with-attrs
     (jetpacs-surface :color hex :shape "circle")
     :width (or size 22) :height (or size 22))))

(defun jetpacs-theme-picker-display-name (prefix theme)
  "A human-friendly label for THEME: drop PREFIX, then title-case,
so `modus-operandi-tinted' reads as \"Operandi Tinted\"."
  (capitalize
   (replace-regexp-in-string
    "-" " " (string-remove-prefix prefix (symbol-name theme)))))

(defun jetpacs-theme-picker-strip (color-fn)
  "The CURRENT theme's swatch strip: one chip per strip key.
COLOR-FN takes (KEY &optional THEME) and returns a hex string or nil;
called with no theme it reads the live palette, which resolves on every
provider version."
  (delq nil (mapcar (lambda (key)
                      (jetpacs-theme-picker--swatch (funcall color-fn key)))
                    jetpacs-theme-picker-strip-keys)))

(defun jetpacs-theme-picker-preview (color-fn theme)
  "Per-theme swatches (background / foreground / accent) for THEME's row.
Only when the running palette machinery can resolve a NON-current
theme's colors (`modus-themes-activate', modus 5.0+); otherwise nil, so
the list shows uniformly clean names instead of swatches for the active
theme alone."
  (when (fboundp 'modus-themes-activate)
    (delq nil (mapcar (lambda (key)
                        (jetpacs-theme-picker--swatch
                         (funcall color-fn key theme) 18))
                      '(bg-main fg-main accent-0)))))

(defun jetpacs-theme-picker-mirror-note (mirror-action)
  "Companion-mirror status: a live badge, or a one-tap switch to mirror mode.
MIRROR-ACTION is the action that flips `jetpacs-theme-mode' to `mirror'."
  (if (eq jetpacs-theme-mode 'mirror)
      (jetpacs-row (jetpacs-icon "smartphone" :size 16)
                   (jetpacs-text "Mirroring to the companion"
                                 :style "caption"))
    (jetpacs-chip "Mirror on phone" :icon "smartphone"
                  :on-tap (jetpacs-action mirror-action))))

(cl-defun jetpacs-theme-picker-current-card (current &key display-fn
                                                       dark-p-fn color-fn
                                                       mirror-action
                                                       none-label)
  "The header card: the active theme's name, polarity, palette, mirror status.
CURRENT is the active theme symbol or nil (NONE-LABEL shows then);
DISPLAY-FN renders its title, DARK-P-FN its polarity, COLOR-FN feeds the
palette strip, and MIRROR-ACTION the mirror note."
  (jetpacs-card
   (apply #'jetpacs-column
          (delq nil
                (list (jetpacs-text (if current (funcall display-fn current)
                                      none-label)
                                    :style "title")
                      (when current
                        (jetpacs-text (concat (if (funcall dark-p-fn current)
                                                  "Dark" "Light")
                                              " · " (symbol-name current))
                                      :style "caption"))
                      (when current
                        (apply #'jetpacs-row
                               (jetpacs-theme-picker-strip color-fn)))
                      (when current
                        (jetpacs-theme-picker-mirror-note mirror-action)))))))

(cl-defun jetpacs-theme-picker-theme-card (theme current &key display-fn
                                                   color-fn load-action)
  "A single-line row for THEME: name, preview swatches, and a marker; a tap
dispatches LOAD-ACTION with the theme name.  CURRENT (the active theme)
is checked and not re-loadable.  The swatches are spread as direct row
children (a nested `row' fills the width and would starve the weighted
name); polarity is omitted — the cards are already grouped under
Light/Dark headers."
  (let ((activep (eq theme current)))
    (jetpacs-card
     (apply #'jetpacs-row
            (append
             (list (jetpacs-with-attrs
                    (jetpacs-box (jetpacs-text (funcall display-fn theme)
                                               :style "label"))
                    :weight 1))
             (jetpacs-theme-picker-preview color-fn theme)
             (list (if activep
                       (jetpacs-icon "check_circle" :color "primary")
                     (jetpacs-icon "chevron_right")))))
     :on-tap (unless activep
               (jetpacs-action load-action
                               :args (list :theme (symbol-name theme)))))))

(cl-defun jetpacs-theme-picker-themes-section (themes current &key dark-p-fn
                                                        display-fn color-fn
                                                        load-action)
  "The theme picker: THEMES as cards grouped Light then Dark."
  (let* ((light (seq-remove dark-p-fn themes))
         (dark (seq-filter dark-p-fn themes))
         (card (lambda (theme)
                 (jetpacs-theme-picker-theme-card theme current
                                                    :display-fn display-fn
                                                    :color-fn color-fn
                                                    :load-action load-action))))
    (append
     (when light (cons (jetpacs-section-header "Light") (mapcar card light)))
     (when dark (cons (jetpacs-section-header "Dark") (mapcar card dark))))))

(defun jetpacs-theme-picker-more-link (group)
  "A card cross-linking into the customize browser's GROUP."
  (jetpacs-card
   (jetpacs-row
    (jetpacs-icon "tune")
    (jetpacs-with-attrs
     (jetpacs-box (jetpacs-text "More options in Customize" :style "label"))
     :weight 1)
    (jetpacs-icon "chevron_right"))
   :on-tap (jetpacs-action "customize.show" :args (list :group group))))

(provide 'jetpacs-theme-picker)
;;; jetpacs-theme-picker.el ends here
