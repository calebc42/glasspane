;;; jetpacs-theme.el --- Mirror the Emacs theme onto the Companion -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JA-1 of docs/PLAN-jetpacs-apps.md: device coherence.  The Tier-0
;; renderer already emits per-span hexes from live faces, so without a
;; mirrored palette the device shows Emacs-theme text inside
;; Material-You chrome.  This module closes that: it extracts the
;; active theme's palette (modus-family semantic roles when available,
;; face resolution otherwise) and pushes it through `ebp-client-theme-set'
;; (SPEC 18.4), following every `load-theme' with a debounce.
;;
;; A rebuild-lite of poc-v1 `jetpacs-theme.el' + the surviving slice of
;; `jetpacs-modus.el'.  What changed under the port:
;; - SPEC 18.4 deleted the poc's `base' directive, so the mode enum is
;;   rebuilt as the four 18.4-expressible states: `system' (default —
;;   amendment #36: dark OMITTED = follow the device), `light', `dark',
;;   `mirror'.
;; - Colors/syntax are keyword PLISTS for the jsonrpc path, not alists.
;; - Syntax values are SyntaxStyle OBJECTS (:fg HEX) — the Companion's
;;   syntaxFg reads only fg, and a JSON array in a role slot is ignored
;;   outright, so the poc's heading/paren VECTORS are dead wire:
;;   heading is emitted as ONE style, paren not at all.
;; - Every emitted role is a REGISTERED contract syntax role.  The
;;   `:meta' compat duplicate of `:preprocessor' died with amendment
;;   #126 option B: the Companion now reads `preprocessor' (meta lines)
;;   and `tag' (org tags) and ignores unregistered names, as 18.4
;;   requires of every conforming receiver.
;; - The poc's global `jetpacs-connected-hook' is gone; the re-push on
;;   reconnect rides a per-client ready hook that `jetpacs-connect'
;;   wires under `fboundp', like the shell drain.
;;
;; Desktop-untouched: the theme hooks run on every `load-theme' for the
;; life of the session, so their first effective test is a cheap mode
;; check and then `jetpacs-connected-p' — a disconnected Emacs pays one
;; `eq' per theme switch and nothing else.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-modus)
(require 'ebp)
(require 'jetpacs-surfaces)

(defgroup jetpacs-theme nil
  "Mirroring the Emacs theme onto the Companion."
  :group 'jetpacs)

;; Modus is version-adaptive territory: 5.x has a derivative registry
;; and enumeration API that 4.4 (Emacs 30's bundled copy) lacks, so
;; every 5.x call sits behind `fboundp' — these are library-version
;; guards, not 30.1 compat shims.  Declares cover exactly what is
;; called; `modus-themes-load-theme' is deliberately NOT declared (the
;; poc declared it with a stale arity and never needed it; neither do we).
(declare-function modus-themes-get-color-value "modus-themes"
                  (color &optional overrides theme))
(declare-function modus-themes-get-current-theme "modus-themes" ())
(declare-function modus-themes-get-all-known-themes "modus-themes"
                  (&optional family))
(declare-function modus-themes-toggle "modus-themes" ())
(defvar modus-themes-items)
(defvar modus-themes-to-toggle)

(defcustom jetpacs-theme-mode 'system
  "Which color scheme the Companion uses (SPEC 18.4).

`system' — the Companion's native scheme, following the device's own
           light/dark setting (`dark' omitted on the wire, amendment #36).
`light'  — the native scheme, forced light.
`dark'   — the native scheme, forced dark.
`mirror' — the active Emacs theme's palette and syntax colors, polarity
           forced from the theme's own background, following every
           `load-theme'.
`off'    — base NEVER touches `theme.set': no READY frame, no
           `load-theme' follow, no clear.  The mode for a session where
           a Tier-1 owns the palette — pre-fix, merely LOADING this
           file made the default `system' mode CLEAR a Tier-1's
           persisted mirror 0.2 s after every READY.

Every push is a complete replacement, so the three non-mirror modes
also clear any mirrored palette the Companion had persisted.  Setting
this through Customize or `setopt' applies immediately on a live
connection; after a plain `setq', push with \\[jetpacs-theme-send] or
reconnect."
  :type '(choice (const :tag "Follow the device" system)
                 (const :tag "Native, forced light" light)
                 (const :tag "Native, forced dark" dark)
                 (const :tag "Mirror the Emacs theme" mirror)
                 (const :tag "Off — never touch theme.set" off))
  :set (lambda (sym val)
         (set-default sym val)
         ;; Live apply (guarded: :set also runs while this file loads,
         ;; before the functions below exist).
         (when (and (featurep 'jetpacs-theme) (jetpacs-connected-p)
                    (not (eq val 'off)))
           (jetpacs-theme--push-mode))))

(defcustom jetpacs-theme-dynamic nil
  "When non-nil, ask for the device\='s wallpaper-derived Material You
palette as the BASE scheme (SPEC 18.4 `dynamic\=').  Emacs could never
send that palette as colors — it derives from the wallpaper, which
never reaches Emacs — so this is a request, honored where the platform
has dynamic color and the baseline scheme standing in elsewhere.
Pushed colors still overlay the base.  Applies immediately on a live
connection through Customize or `setopt\='."
  :type 'boolean
  :set (lambda (sym val)
         (set-default sym val)
         (when (and (featurep 'jetpacs-theme) (jetpacs-connected-p))
           (jetpacs-theme--push-mode))))

(defcustom jetpacs-theme-font-scale nil
  "A number 0.4..2.0 scaling every text node together, or nil.
nil follows the device\='s own font-size setting (SPEC 18.4
`font_scale\=' absent).  One number for the whole surface — a per-node
member would be the wrong shape.  Applies immediately on a live
connection through Customize or `setopt\='."
  :type '(choice (const :tag "Follow the device" nil)
                 (number :tag "Scale factor (0.4..2.0)"))
  :set (lambda (sym val)
         (when (and val (not (and (numberp val) (<= 0.4 val 2.0))))
           (error "jetpacs-theme-font-scale must be nil or a number in 0.4..2.0"))
         (set-default sym val)
         (when (and (featurep 'jetpacs-theme) (jetpacs-connected-p))
           (jetpacs-theme--push-mode))))

(defcustom jetpacs-theme-layout-direction 'system
  "The Companion\='s layout direction (SPEC 18.4 `layout_direction\=').
`system\=' follows the device (the member stays absent — the same
tri-state convention as `dark\='); `ltr\='/`rtl\=' force it, mirroring
every start/end pad, arrange and align on the surface.  Applies
immediately on a live connection through Customize or `setopt\='."
  :type '(choice (const :tag "Follow the system" system)
                 (const :tag "Left to right" ltr)
                 (const :tag "Right to left" rtl))
  :set (lambda (sym val)
         (set-default sym val)
         (when (and (featurep 'jetpacs-theme) (jetpacs-connected-p))
           (jetpacs-theme--push-mode))))

;;;; Color plumbing (ported verbatim; the JC-1 tty lesson lives in --rgb)

(defun jetpacs-theme--rgb (color)
  "COLOR (a name or #RRGGBB string) as a list of three [0,1] floats, or nil.
Hex strings are parsed directly — `color-name-to-rgb' resolves through
the current display, which on a tty/batch frame quantizes #2e3440 to the
nearest terminal color — so theme hexes stay exact on every frame type.
nil for the `unspecified-fg'/`unspecified-bg' placeholders a batch or tty
frame reports, and for anything the display can't resolve."
  (cond
   ((not (stringp color)) nil)
   ((string-prefix-p "unspecified" color) nil)
   ((string-match "\\`#\\([[:xdigit:]]+\\)\\'" color)
    (let* ((hex (match-string 1 color))
           (digits (/ (length hex) 3)))
      (when (and (> digits 0) (= (% (length hex) 3) 0))
        (let ((max (float (1- (expt 16 digits)))))
          (mapcar (lambda (i)
                    (/ (string-to-number
                        (substring hex (* i digits) (* (1+ i) digits))
                        16)
                       max))
                  '(0 1 2))))))
   (t (color-name-to-rgb color))))

(defun jetpacs-theme--hex (color)
  "COLOR normalized to \"#rrggbb\", or nil when unresolvable."
  (when-let* ((rgb (jetpacs-theme--rgb color)))
    (apply #'format "#%02x%02x%02x"
           (mapcar (lambda (c) (min 255 (round (* 255 c)))) rgb))))

(defun jetpacs-theme--blend (a b frac)
  "FRAC of color A mixed into (1 - FRAC) of color B, as hex; nil on failure."
  (let ((ra (jetpacs-theme--rgb a))
        (rb (jetpacs-theme--rgb b)))
    (when (and ra rb)
      (apply #'format "#%02x%02x%02x"
             (cl-mapcar (lambda (ca cb)
                          (min 255 (round (* 255 (+ (* frac ca)
                                                    (* (- 1.0 frac) cb))))))
                        ra rb)))))

(defun jetpacs-theme--dark-p (color)
  "Non-nil when COLOR reads as a dark background (relative luminance < 0.5)."
  (when-let* ((rgb (jetpacs-theme--rgb color)))
    (< (+ (* 0.2126 (nth 0 rgb))
          (* 0.7152 (nth 1 rgb))
          (* 0.0722 (nth 2 rgb)))
       0.5)))

(defun jetpacs-theme--face-color (attr &rest faces)
  "Inheritance-resolved ATTR of the first of FACES with a usable color, as hex."
  (catch 'hit
    (dolist (f faces)
      (when (facep f)
        (when-let* ((hex (jetpacs-theme--hex (face-attribute f attr nil t))))
          (throw 'hit hex))))
    nil))

;;;; Modus palette access

(defun jetpacs-theme--modus-theme ()
  "The active modus-family theme (a modus theme or a derivative), or nil.

Modus 5.0 turned modus into a platform: a derivative registers via
`modus-themes-theme' and `modus-themes-get-current-theme' returns the
enabled theme bearing the registry property — the whole family, not
just the `modus-' originals.  On 4.x (Emacs 30's bundled copy) that
registry does not exist, so fall back to a name-prefix match: 4.x still
has the palette accessor and the same semantic mappings, it just cannot
enumerate derivatives."
  (cond
   ((fboundp 'modus-themes-get-current-theme)
    (modus-themes-get-current-theme))
   ((fboundp 'modus-themes-get-color-value)
    (cl-find-if (lambda (theme)
                  (string-prefix-p "modus-" (symbol-name theme)))
                custom-enabled-themes))))

(defun jetpacs-theme--modus-p ()
  "Non-nil when a modus-family theme is active and its palette API is usable."
  (and (fboundp 'modus-themes-get-color-value)
       (jetpacs-theme--modus-theme)
       t))

(defun jetpacs-theme--modus (key &optional theme)
  "Hex value of modus palette color KEY, or nil.
Without THEME, read the ACTIVE theme's value WITH overrides, so the
user's `modus-themes-common-palette-overrides' are mirrored.  With
THEME, read that theme's stock value (preview semantics — no
overrides).  A KEY absent from the palette yields the `unspecified'
symbol, which the `stringp' guard drops."
  (when-let* ((value (ignore-errors
                       (if theme
                           (modus-themes-get-color-value key nil theme)
                         (modus-themes-get-color-value key :with-overrides)))))
    (and (stringp value) (jetpacs-theme--hex value))))

;;;; Palette construction

(defun jetpacs-theme--compact-plist (pairs)
  "PAIRS, a list of (KEYWORD . VALUE), as a plist without nil values."
  (let (plist)
    (dolist (p pairs)
      (when (cdr p)
        (push (car p) plist)
        (push (cdr p) plist)))
    (nreverse plist)))

(defun jetpacs-theme--colors ()
  "The wire color-role plist for the active theme, or nil when unresolvable.

Role mapping follows Material grammar, not face taxonomy: `primary' is
the theme's IDENTITY accent — under modus `accent-0', the palette's
designated primary (a derivative whose identity hue is green gets a
green FAB, not a hardcoded blue one); otherwise the keyword face, where
theme authors put their signature hue.  The link face is deliberately
NOT primary: links are blue in nearly every theme regardless of its
identity.  `secondary' is the same hue muted (never modus `accent-1',
a competing hue); `tertiary' is the contrasting accent (`accent-2' /
constant face); `error' is modus's semantic `err', so the deuteranopia
variants stay accessible.  `success'/`warning' feed the Companion's
ExtendedColors (no Material slot): success is modus `info' — modus's
own styling of the `success' face — else the `success' face."
  (let* ((modus (jetpacs-theme--modus-p))
         (bg (or (and modus (jetpacs-theme--modus 'bg-main))
                 (jetpacs-theme--face-color :background 'default)))
         (fg (or (and modus (jetpacs-theme--modus 'fg-main))
                 (jetpacs-theme--face-color :foreground 'default))))
    (when (and bg fg)
      (let* ((primary (or (and modus (jetpacs-theme--modus 'accent-0))
                          (jetpacs-theme--face-color
                           :foreground 'font-lock-keyword-face 'link
                           'font-lock-function-name-face)
                          fg))
             ;; Muted primary: sink it halfway into the theme's mid-gray,
             ;; like Material's low-chroma secondary tonal palette.
             (secondary (or (jetpacs-theme--blend
                             primary (jetpacs-theme--blend fg bg 0.5) 0.5)
                            primary))
             (tertiary (or (and modus (jetpacs-theme--modus 'accent-2))
                           (jetpacs-theme--face-color
                            :foreground 'font-lock-constant-face)
                           secondary))
             (err (or (and modus (jetpacs-theme--modus 'err))
                      (jetpacs-theme--face-color :foreground 'error)
                      "#b3261e"))
             (success (or (and modus (jetpacs-theme--modus 'info))
                          (jetpacs-theme--face-color :foreground 'success)))
             (warning (or (and modus (jetpacs-theme--modus 'warning))
                          (jetpacs-theme--face-color :foreground 'warning)))
             ;; Container tone: sink each resolved accent most of the way
             ;; into the background — blending the actual accent tracks
             ;; any derivative or override, where modus's `bg-*-subtle'
             ;; tints are keyed to fixed hues.
             (container (lambda (accent)
                          (jetpacs-theme--blend accent bg 0.22)))
             (on-container (lambda (accent)
                             (if modus fg
                               (jetpacs-theme--blend accent fg 0.35)))))
        (jetpacs-theme--compact-plist
         `((:primary . ,primary)
           (:on_primary . ,bg)
           (:primary_container . ,(funcall container primary))
           (:on_primary_container . ,(funcall on-container primary))
           (:secondary . ,secondary)
           (:on_secondary . ,bg)
           (:secondary_container . ,(funcall container secondary))
           (:on_secondary_container . ,(funcall on-container secondary))
           (:tertiary . ,tertiary)
           (:on_tertiary . ,bg)
           (:tertiary_container . ,(funcall container tertiary))
           (:on_tertiary_container . ,(funcall on-container tertiary))
           (:error . ,err)
           (:on_error . ,bg)
           (:error_container . ,(funcall container err))
           (:on_error_container . ,(funcall on-container err))
           (:background . ,bg)
           (:on_background . ,fg)
           (:surface . ,bg)
           (:on_surface . ,fg)
           (:surface_variant . ,(or (and modus (jetpacs-theme--modus 'bg-dim))
                                    (jetpacs-theme--face-color
                                     :background 'mode-line-inactive)
                                    (jetpacs-theme--blend fg bg 0.08)))
           (:on_surface_variant . ,(or (and modus (jetpacs-theme--modus 'fg-dim))
                                       (jetpacs-theme--face-color
                                        :foreground 'mode-line-inactive)
                                       fg))
           (:outline . ,(or (and modus (jetpacs-theme--modus 'border))
                            (jetpacs-theme--face-color :foreground 'shadow)
                            (jetpacs-theme--blend fg bg 0.5)))
           (:success . ,success)
           (:warning . ,warning)))))))

;;;; Syntax roles (SyntaxStyle objects — SPEC 18.4)

(defun jetpacs-theme--style (hex)
  "HEX (or nil) as the SyntaxStyle plist (:fg HEX), or nil.
The single place syntax values are boxed; fg-only by design — the
Companion's syntaxFg reads only fg, and 18.4 makes the other members
advisory."
  (when hex (list :fg hex)))

(defun jetpacs-theme--syntax ()
  "Editor token-style plist for the active theme.
Missing values are omitted and the Companion keeps its static color for
that token.  Under a modus-family theme the palette's semantic code
roles are read (exact even in a batch/tty frame, and accessible on the
deuteranopia/tritanopia variants); otherwise font-lock and org faces."
  (if (jetpacs-theme--modus-p)
      (jetpacs-theme--syntax-modus)
    (jetpacs-theme--syntax-faces)))

(defun jetpacs-theme--syntax-modus ()
  "Token styles from modus's semantic palette mappings.
`number' has no modus role of its own, so it tracks `constant'.
`heading' is ONE style (a vector in a role slot is ignored by the
device — the poc's rainbow walk is dead wire); a single heading fg
uniformly recolors the Companion's level rainbow, which is mirror
fidelity by choice.  `operator' is absent from 4.4's palette and
compacts away there."
  (let ((pre (jetpacs-theme--style (jetpacs-theme--modus 'preprocessor))))
    (jetpacs-theme--compact-plist
     `((:comment . ,(jetpacs-theme--style (jetpacs-theme--modus 'comment)))
       (:string . ,(jetpacs-theme--style (jetpacs-theme--modus 'string)))
       (:keyword . ,(jetpacs-theme--style (jetpacs-theme--modus 'keyword)))
       (:function . ,(jetpacs-theme--style (jetpacs-theme--modus 'fnname)))
       (:constant . ,(jetpacs-theme--style (jetpacs-theme--modus 'constant)))
       (:variable . ,(jetpacs-theme--style (jetpacs-theme--modus 'variable)))
       (:type . ,(jetpacs-theme--style (jetpacs-theme--modus 'type)))
       (:number . ,(jetpacs-theme--style (jetpacs-theme--modus 'constant)))
       (:operator . ,(jetpacs-theme--style (jetpacs-theme--modus 'operator)))
       (:preprocessor . ,pre)
       (:heading . ,(jetpacs-theme--style
                     (jetpacs-theme--modus 'fg-heading-1)))
       (:link . ,(jetpacs-theme--style (jetpacs-theme--modus 'fg-link)))
       (:todo . ,(jetpacs-theme--style (jetpacs-theme--modus 'prose-todo)))
       (:done . ,(jetpacs-theme--style (jetpacs-theme--modus 'prose-done)))
       (:tag . ,(jetpacs-theme--style (jetpacs-theme--modus 'prose-tag)))))))

(defun jetpacs-theme--syntax-faces ()
  "Token styles from the theme's font-lock/org/outline faces."
  (let ((pre (jetpacs-theme--style
              (jetpacs-theme--face-color
               :foreground 'font-lock-preprocessor-face 'shadow))))
    (jetpacs-theme--compact-plist
     `((:comment . ,(jetpacs-theme--style
                     (jetpacs-theme--face-color
                      :foreground 'font-lock-comment-face)))
       (:string . ,(jetpacs-theme--style
                    (jetpacs-theme--face-color
                     :foreground 'font-lock-string-face)))
       (:keyword . ,(jetpacs-theme--style
                     (jetpacs-theme--face-color
                      :foreground 'font-lock-keyword-face)))
       (:function . ,(jetpacs-theme--style
                      (jetpacs-theme--face-color
                       :foreground 'font-lock-function-name-face)))
       (:constant . ,(jetpacs-theme--style
                      (jetpacs-theme--face-color
                       :foreground 'font-lock-constant-face)))
       (:variable . ,(jetpacs-theme--style
                      (jetpacs-theme--face-color
                       :foreground 'font-lock-variable-name-face)))
       (:type . ,(jetpacs-theme--style
                  (jetpacs-theme--face-color
                   :foreground 'font-lock-type-face)))
       (:number . ,(jetpacs-theme--style
                    (jetpacs-theme--face-color
                     :foreground 'font-lock-number-face
                     'font-lock-constant-face)))
       (:operator . ,(jetpacs-theme--style
                      (jetpacs-theme--face-color
                       :foreground 'font-lock-operator-face)))
       (:preprocessor . ,pre)
       (:heading . ,(jetpacs-theme--style
                     (jetpacs-theme--face-color :foreground 'outline-1)))
       (:link . ,(jetpacs-theme--style
                  (jetpacs-theme--face-color :foreground 'link)))
       (:todo . ,(jetpacs-theme--style
                  (jetpacs-theme--face-color :foreground 'org-todo 'error)))
       (:done . ,(jetpacs-theme--style
                  (jetpacs-theme--face-color :foreground 'org-done 'success)))
       (:tag . ,(jetpacs-theme--style
                 (jetpacs-theme--face-color :foreground 'org-tag)))))))

;;;; Payload and the mode matrix

(defun jetpacs-theme-payload ()
  "The full mirror args for `ebp-client-theme-set', or nil.
nil means the frame can't resolve colors (a batch/tty non-modus frame) —
callers MUST NOT push then: 18.4 makes every notification a complete
replacement, so a colorless session would wipe a good persisted
palette.  Mirror FORCES polarity from the theme's own surface: with
`dark' absent the Companion would base hole-filling on the device
setting, and a dark palette over a light base fills every unpushed role
from the wrong side."
  (when-let* ((colors (jetpacs-theme--colors)))
    (list :dark (if (jetpacs-theme--dark-p (plist-get colors :surface))
                    t :false)
          :colors colors
          :syntax (jetpacs-theme--syntax))))

(defun jetpacs-theme--frame-args ()
  "The `ebp-client-theme-set' args for `jetpacs-theme-mode', or nil.
The SPEC 18.4 mode matrix: `system' omits `dark' entirely (amendment
#36 — follow the device); the bare symbol `null' clears colors/syntax
\(the seam normalizes it to JSON null); `mirror' yields the payload, or
nil when the frame is colorless — the caller must not push nil."
  (pcase jetpacs-theme-mode
    ('mirror (jetpacs-theme-payload))
    ('light '(:dark :false :colors null :syntax null))
    ('dark '(:dark t :colors null :syntax null))
    (_ '(:colors null :syntax null))))

;;;; Pushing

(defvar jetpacs-theme--timer nil
  "Debounce timer for automatic pushes, or nil.")

(defvar jetpacs-theme-payload-function nil
  "When non-nil, a nullary function returning `ebp-client-theme-set' args.
The EXPLICIT payload seam: a Tier-1 that computes its own palette (say,
from modus 5.0's theme-building API) sets this and base's machinery —
the READY paint, the `load-theme' follow, the debounce, the grant gate —
becomes its transport instead of its competitor.  A nil return means
\"nothing to push\" and the send is skipped, same as the mirror's own
unresolvable-frame case.")

(defun jetpacs-theme--send-now ()
  "Send the current mode's frame immediately; the gated, final send.
Every automatic path funnels here: mode `off' emits NOTHING (not even a
clear), an explicit `jetpacs-theme-payload-function' wins over the mode
matrix, and the gate re-checks connection and grant at send time — the
connection can die, or be replaced by a session that did not grant
theme, between the decision to push and the push."
  (when (and (not (eq jetpacs-theme-mode 'off))
             (jetpacs-connected-p) (jetpacs-granted-p "theme"))
    (when-let* ((args (if jetpacs-theme-payload-function
                          (funcall jetpacs-theme-payload-function)
                        (jetpacs-theme--frame-args))))
      (condition-case err
          (apply #'ebp-client-theme-set (jetpacs-client)
                 ;; 18.4: every push is a COMPLETE replacement, so the
                 ;; presentation trio rides every frame — dropping it
                 ;; from one push would silently reset all three.
                 (append args (jetpacs-theme--trio-args)))
        (error (message "jetpacs-theme: push failed: %s"
                        (jetpacs--error-label err)))))))

(defun jetpacs-theme--trio-args ()
  "The SPEC 18.4 device-presentation trio, appended to every push.
Each member stays ABSENT at its default so the device/system setting
rules — the tri-state `dark' convention."
  `(,@(when jetpacs-theme-dynamic '(:dynamic t))
    ,@(when jetpacs-theme-font-scale
        `(:font-scale ,jetpacs-theme-font-scale))
    ,@(unless (eq jetpacs-theme-layout-direction 'system)
        `(:layout-direction ,(symbol-name jetpacs-theme-layout-direction)))))

(defun jetpacs-theme--push-mode (&rest _)
  "Debounced push of the current mode's frame.
The debounce exists for `load-theme', which fires disable+enable back
to back; `jetpacs-theme--send-now' re-gates inside the timer because
the session can change in 0.2 s.  Mode `off' arms nothing."
  (when (and (not (eq jetpacs-theme-mode 'off))
             (jetpacs-connected-p) (jetpacs-granted-p "theme"))
    (when (timerp jetpacs-theme--timer)
      (cancel-timer jetpacs-theme--timer))
    (setq jetpacs-theme--timer
          (run-at-time
           0.2 nil
           (lambda ()
             (setq jetpacs-theme--timer nil)
             (jetpacs-theme--send-now))))))

(defun jetpacs-theme-send ()
  "Push the active Emacs theme's palette to the Companion, once.
Works regardless of `jetpacs-theme-mode' — a manual one-shot mirror."
  (interactive)
  (cond
   ((not (jetpacs-connected-p))
    (message "Jetpacs: not connected"))
   ((not (jetpacs-granted-p "theme"))
    (message "Jetpacs: companion did not grant theme (check :wants)"))
   (t
    (let ((payload (jetpacs-theme-payload)))
      (if (null payload)
          (message "Jetpacs: this frame reports no usable theme colors")
        (apply #'ebp-client-theme-set (jetpacs-client) payload)
        (message "Jetpacs: theme pushed"))))))

(defun jetpacs-theme-clear ()
  "Revert the Companion to its native scheme, following the device polarity.
Sends the bare clear — colors and syntax null, `dark' omitted (#36)."
  (interactive)
  (if (not (and (jetpacs-connected-p) (jetpacs-granted-p "theme")))
      (message "Jetpacs: not connected with the theme grant")
    (ebp-client-theme-set (jetpacs-client) :colors 'null :syntax 'null)))

;;;; Hooks: follow load-theme live; re-push on every reconnect

(defun jetpacs-theme--on-theme-change (&rest _)
  "Re-mirror on a live theme switch, but only while mirroring.
The non-mirror modes don't depend on the Emacs theme; their frame rides
the ready hook and the mode's `:set'.  Disconnected desktop Emacs pays
one `eq' here per `load-theme' and nothing else."
  (when (eq jetpacs-theme-mode 'mirror)
    (jetpacs-theme--push-mode)))

(defun jetpacs-theme--on-ready (_client)
  "Per-client READY hook: paint the chrome for the configured mode.
Wired by `jetpacs-connect' under `fboundp' — READY fires after the
welcome absorbed the grant set, so the gate inside the send is
answerable.  SYNCHRONOUS, not debounced: the debounce exists for
`load-theme''s disable+enable pair, and deferring the FIRST frame was a
0.2 s wrong-palette flash on every pairing — the ordering comment in
the shell (\"chrome is painted before content arrives\") was not
actually delivered until this sent inline."
  (jetpacs-theme--send-now))

(defun jetpacs-theme--on-teardown (owner)
  "Cancel the pending debounce when the theme owner is torn down."
  (when (equal owner "jetpacs.theme")
    (when (timerp jetpacs-theme--timer)
      (cancel-timer jetpacs-theme--timer)
      (setq jetpacs-theme--timer nil))))

(add-hook 'jetpacs-teardown-functions #'jetpacs-theme--on-teardown)

(add-hook 'enable-theme-functions #'jetpacs-theme--on-theme-change)
(add-hook 'disable-theme-functions #'jetpacs-theme--on-theme-change)

;;;; modus.toggle — the one device-facing verb of this rung

(with-jetpacs-owner "jetpacs.theme"
  (jetpacs-defaction "jetpacs.theme.modus-toggle"
    (lambda (_args _params)
      ;; The length-2 pre-check keeps 4.4's completing-read fallback out
      ;; of the dispatch extent (D2): with any other toggle set,
      ;; `modus-themes-toggle' PROMPTS, and the no-prompts regime would
      ;; convert that into a loud warning instead of a clean refusal.
      ;; No push of any kind here: theme owns no surface, and the
      ;; observable effect — theme.set — rides the enable-theme hook's
      ;; debounce, firing outside this extent.
      (if (not (and (jetpacs-modus--ensure)
                    (fboundp 'modus-themes-toggle)
                    (boundp 'modus-themes-to-toggle)
                    (= 2 (length modus-themes-to-toggle))))
          'rejected
        (condition-case err
            (progn (modus-themes-toggle) 'accepted)
          (error (message "jetpacs-theme: modus.toggle failed: %s"
                          (jetpacs--error-label err))
                 'rejected))))
    ;; A GLOBAL VERB: theme owns no surface, and ANY surface may render
    ;; its button — without this the dispatch's D1 scope would reject
    ;; every real tap (a surface event always carries `surface').
    :any-surface t))

(provide 'jetpacs-theme)
;;; jetpacs-theme.el ends here
