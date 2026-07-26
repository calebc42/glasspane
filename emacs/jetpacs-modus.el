;;; jetpacs-modus.el --- Hook-free modus-theme queries -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The version-adaptive modus queries, split out of `jetpacs-theme' so a
;; Tier-1 building on modus 5.0's public theme-building API (the
;; JA-10 screen substrate) can require THIS file without arming any of
;; the theme module's machinery.  HOOK-FREE BY CONTRACT: loading this
;; file must observably change nothing — no hooks, no advice, no ready
;; functions, no timers.  Everything here is a pure query plus one
;; interactive command; `jetpacs-theme' requires it and re-exports
;; nothing (the names are already public).

;;; Code:

(require 'seq)

;;;; Modus queries (version-adaptive; public — JA-10's screen substrate)

(defun jetpacs-modus-available-p ()
  "Non-nil when the built-in modus themes are installed in this Emacs."
  (and (seq-some (lambda (theme)
                   (string-prefix-p "modus-" (symbol-name theme)))
                 (custom-available-themes))
       t))

(defun jetpacs-modus--ensure ()
  "Load the modus-themes library without enabling a theme; non-nil on success.
The library lives in the themes directory rather than on `load-path', so
`require-theme' is the reliable loader; a plain `require' covers the
on-load-path case, and `featurep' the case where a modus theme is
already active."
  (or (featurep 'modus-themes)
      (require 'modus-themes nil t)
      (and (ignore-errors (require-theme 'modus-themes t))
           (featurep 'modus-themes))))

(defun jetpacs-modus-themes ()
  "Selectable modus themes: the stock set, plus derivatives where supported."
  (cond ((fboundp 'modus-themes-get-all-known-themes)
         (modus-themes-get-all-known-themes))
        ((boundp 'modus-themes-items) modus-themes-items)))

(defun jetpacs-modus-current ()
  "The active modus theme symbol, or nil."
  (if (fboundp 'modus-themes-get-current-theme)
      (modus-themes-get-current-theme)
    (let ((known (jetpacs-modus-themes)))
      (seq-find (lambda (theme) (memq theme known)) custom-enabled-themes))))

(defun jetpacs-modus-dark-p (theme)
  "Non-nil when THEME reads as a dark modus theme.
Prefer the theme's own `:background-mode' property (set by 4.4's stock
themes and the 5.0 registry); fall back to the stock naming, where
every `vivendi' is dark and every `operandi' light."
  (let ((props (get theme 'theme-properties)))
    (if (plist-member props :background-mode)
        (eq (plist-get props :background-mode) 'dark)
      (and (string-match-p "vivendi" (symbol-name theme)) t))))

(defun jetpacs-modus-toggle ()
  "Toggle between the two `modus-themes-to-toggle' themes.
The desktop face of the `modus.toggle' action; interactively, 4.x's
`completing-read' fallback (when the toggle pair isn't two themes) is
fine — there is a user at the keyboard."
  (interactive)
  (if (and (jetpacs-modus--ensure) (fboundp 'modus-themes-toggle))
      (modus-themes-toggle)
    (message "Jetpacs: modus themes are not available in this Emacs")))

(provide 'jetpacs-modus)
;;; jetpacs-modus.el ends here
