;;; glasspane-packages.el --- Self-provisioning of the optional org engines -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; org-ql (kept only as an installable engine — v3 never dispatches to
;; it), vulpea (backlinks, note completion, the stale-file half of
;; Review), org-srs (the Review screen), ef-themes (the Ef Themes
;; picker — a MELPA package, unlike the built-in modus themes): all
;; optional, all degrading cleanly — and on a fresh device nothing else
;; ever installs them, so a degraded install would dead-end forever:
;; no Review entry, no backlinks, and restarting could never help.
;; The app provisions its OWN engines: one automatic attempt per
;; interactive session when the app is store-installed and something is
;; missing, the `glasspane.packages.install' action as the on-demand
;; path, and `M-x glasspane-packages-ensure' as the desktop path.
;; Success lights features up live — probes re-ask, vulpea autosync
;; wired, shell refreshed — no restart.
;;
;; Trust boundary (the package-browser keeps the same lock): only the
;; closed, app-owned set ever auto-installs.  Nothing on the wire and
;; nothing in org data can name a package.
;;
;; v3 deltas from the v1 file (docs/PLAN-glasspane-app.md, G2):
;; glasspane-pack.el is RETIRED (retirement list: no pack/manifest
;; seam) — its depends floors fold into `glasspane-packages--set';
;; install consent reads `jetpacs-app-store-installed' (T2), and
;; per FOUNDATION-GAPS #4 in-tree/dev loads are never in that list, so
;; dev first-boot seeding is manual (`M-x glasspane-packages-ensure');
;; the install handler defers per D2 (`package-refresh-contents' pumps
;; the event loop) instead of running package.el inside the dispatch.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-settings)
;; The extractor worker-lib (G1): definitions only, safe with vulpea
;; absent — registration happens below, where vulpea is DETECTED.
(require 'glasspane-vulpea)

(declare-function vulpea-db-autosync-mode "ext:vulpea-db" (&optional arg))
(declare-function vulpea-db-sync-full-scan "ext:vulpea-db" ())
(declare-function org-srs-item-confirm-command "ext:org-srs" ())
;; Same-rung sibling: the app-dir seam is glasspane-config's
;; (FOUNDATION-GAPS #4, app-local); this file must load without it.
(declare-function glasspane-config-dir "glasspane-config" ())

;; Forward-declared: these live in org, vulpea-db, org-srs and
;; package.el, none of which this file force-loads — each reference
;; runs only after the owning feature has been required.
(defvar org-directory)
(defvar vulpea-db-sync-directories)
(defvar org-srs-item-confirm)
(defvar package-archives)
(defvar package-archive-contents)

(defcustom glasspane-packages-auto-install t
  "When non-nil, a store install with missing engines schedules one
automatic install attempt per session (on an idle timer, so boot is
never blocked).  The `glasspane.packages.install' action and
`glasspane-packages-ensure' work regardless.  Set to nil (Customize,
or the Settings row this file registers) to manage packages yourself."
  :type 'boolean :group 'jetpacs)

(defconst glasspane-packages--set
  '((org-ql    . "0.7")
    (vulpea    . "2.0")
    (org-srs   . nil)
    (ef-themes . nil))
  "The closed MELPA set the app's optional features read through,
as (PKG . MIN-VERSION) — the retired glasspane-pack's depends floors
folded in (org-ql 0.7+, vulpea 2.0+; org's own 9.6+ floor is subsumed
by the Emacs 30.1 floor's bundled org, and cl-lib is built in — neither
ever installs).  Deliberately not extensible from app data or the
wire — see the trust note above.")

(defvar glasspane-packages--attempted nil
  "Non-nil once this session has scheduled its automatic install attempt.")

(defvar glasspane-packages--installing nil
  "Non-nil while an engine install is in flight.
Load-bearing re-entrancy guard: `package-refresh-contents' pumps the
event loop (`accept-process-output'), so a second tap can dispatch
mid-install — the handler answers from this flag instead of scheduling
a second install.")

(defun glasspane-packages--wanted ()
  "The (PKG . MIN-VERSION) entries this Emacs build can run.
vulpea's index rides SQLite; on a build without it no package install
can help, so vulpea is simply not wanted — search (org-ql) and review
\(org-srs) still are."
  (if (sqlite-available-p)
      glasspane-packages--set
    (remq (assq 'vulpea glasspane-packages--set) glasspane-packages--set)))

(defun glasspane-packages--missing ()
  "The wanted package symbols not currently loadable, freshly probed."
  (cl-remove-if (lambda (pkg) (require pkg nil t))
                (mapcar #'car (glasspane-packages--wanted))))

(defun glasspane-packages--outdated ()
  "The wanted packages package.el installed BELOW their folded floor.
Disjoint from `glasspane-packages--missing', which asks only whether a
package LOADS: an old vulpea 1.x loads fine and so is never missing,
yet the app's features need the floor.  Restricted to package.el's own
installs on purpose — a hand-placed checkout on `load-path' is the
user's copy and is never force-upgraded over."
  (cl-remove-if-not
   (lambda (pkg)
     (let ((min (alist-get pkg (glasspane-packages--wanted))))
       (and min
            (package-installed-p pkg)
            (not (package-installed-p pkg (version-to-list min))))))
   (mapcar #'car (glasspane-packages--wanted))))

(defun glasspane-packages--app-dir ()
  "Glasspane's per-app data directory.
The config sibling owns the seam (FOUNDATION-GAPS #4: app-local, this
rung); until it is loadable the plan-fixed location stands in — both
spell the same directory, so the scan marker below never moves."
  (if (and (require 'glasspane-config nil t)
           (fboundp 'glasspane-config-dir))
      (glasspane-config-dir)
    (expand-file-name "jetpacs/apps/glasspane/" user-emacs-directory)))

(defun glasspane-packages--light-up ()
  "Wire what is now loadable and refresh the shell.
vulpea autosync over the vault (additive — user directories are kept,
one index, and the initial full scan runs once per device via a marker
file) and the command-style org-srs confirm phone-driven review needs.
Then a shell refresh, which re-asks the memoised probes and rebuilds
every pushed view — the Review entry and the notes sections appear
live."
  (when (require 'vulpea nil t)
    ;; vulpea pulled org in, so `org-directory' is bound past here.
    (when (and (stringp org-directory) (file-directory-p org-directory))
      (add-to-list 'vulpea-db-sync-directories org-directory))
    ;; The mobile-context extractor must be in the registry before
    ;; autosync or the once-per-device full scan index anything.
    (glasspane-vulpea-register)
    (when (fboundp 'vulpea-db-autosync-mode)
      (vulpea-db-autosync-mode 1))
    ;; Autosync watches for changes; a vault that predates vulpea still
    ;; needs one full index build.
    (let ((marker (expand-file-name ".vulpea-scanned"
                                    (glasspane-packages--app-dir))))
      (unless (file-exists-p marker)
        (when (fboundp 'vulpea-db-sync-full-scan)
          (ignore-errors (vulpea-db-sync-full-scan)))
        (make-directory (file-name-directory marker) t)
        (write-region "" nil marker nil 'silent))))
  (when (require 'org-srs nil t)
    ;; Upstream's own recommendation for Emacs on Android: the default
    ;; confirm reads a key, which phone-driven review can never answer.
    (setopt org-srs-item-confirm #'org-srs-item-confirm-command))
  (jetpacs-shell-refresh))

(defun glasspane-packages-ensure ()
  "Install any missing or below-floor engine from MELPA, then light up.
Synchronous (package.el is), idempotent, and never signals: returns
non-nil when everything wanted is loadable afterwards, else nil with
the reason in *Messages*.  The retry story is calling this again —
each device boot's automatic attempt and every install tap do exactly
that.  Never called inside a dispatch extent — the action handler
defers here through `jetpacs-flow-continue' (D2)."
  (interactive)
  (cond
   (glasspane-packages--installing
    (message "glasspane-packages: install already in progress")
    nil)
   ;; Both sets gate the install branch, or the floor could never
   ;; bite: an old-but-loadable engine leaves `--missing' empty.
   ((not (or (glasspane-packages--missing) (glasspane-packages--outdated)))
    (glasspane-packages--light-up)
    t)
   (t
    (setq glasspane-packages--installing t)
    (unwind-protect
        (condition-case err
            (progn
              (require 'package)
              (add-to-list 'package-archives
                           '("melpa" . "https://melpa.org/packages/") t)
              (unless (bound-and-true-p package--initialized)
                (package-initialize))
              (package-refresh-contents)
              ;; Two disjoint reasons to install: `--missing' is
              ;; LOADABILITY, `--outdated' is the folded min-version
              ;; floor among package.el's own installs.  A loadable
              ;; checkout package.el never installed is in neither set
              ;; and is deliberately left alone.  The floor case must
              ;; install the ARCHIVE DESC — `package-install' given a
              ;; SYMBOL computes an unversioned requirement and no-ops
              ;; for any installed version (package.el:2247-2251) —
              ;; and a desc install upgrades in place, unlike
              ;; `package-upgrade', which deletes first.
              (let ((outdated (glasspane-packages--outdated)))
                (dolist (pkg (append (glasspane-packages--missing) outdated))
                  (message "glasspane-packages: installing %s…" pkg)
                  (package-install
                   (if (memq pkg outdated)
                       (cadr (assq pkg package-archive-contents))
                     pkg))))
              (let ((still (glasspane-packages--missing)))
                (if still
                    (progn
                      (message
                       "glasspane-packages: %s installed but not loadable — see *Messages*"
                       (mapconcat #'symbol-name still ", "))
                      nil)
                  (glasspane-packages--light-up)
                  (message
                   "glasspane-packages: engines ready — views refreshed")
                  t)))
          (error
           (message "glasspane-packages: install failed: %s"
                    (jetpacs-error-label err))
           nil))
      (setq glasspane-packages--installing nil)))))

(defun glasspane-packages-maybe-auto-install ()
  "Schedule this session's one automatic install when a device needs it.
Fires on an idle timer so load cost is zero.  Only in an interactive
session (batch/CI must never reach for MELPA), only when the app is
store-installed (listed in `jetpacs-app-store-installed' — the same
consent that seeds the managed config; in-tree/dev loads never are,
so dev seeding stays `M-x glasspane-packages-ensure'), at most once a
session, and only when something wanted is actually missing.  Restart =
the natural retry."
  (when (and glasspane-packages-auto-install
             (not noninteractive)
             (not glasspane-packages--attempted)
             (member "glasspane.el"
                     (bound-and-true-p jetpacs-app-store-installed))
             (glasspane-packages--missing))
    (setq glasspane-packages--attempted t)
    (run-with-idle-timer
     3 nil
     (lambda ()
       (message "glasspane-packages: engines missing — attempting install (%s)…"
                (mapconcat #'symbol-name (glasspane-packages--missing) ", "))
       (glasspane-packages-ensure)))))

(defun glasspane-packages--on-install (_args _params)
  "Install the closed engine set — the D2 deferral showcase.
Argument-free: nothing on the wire chooses packages.
`package-refresh-contents' pumps the event loop, so the install runs
in a `jetpacs-flow-continue' continuation (jetpacs-package-browser's
deferred shape); the dispatch answers on the strength of the schedule
and the outcome rides its own toast."
  (if glasspane-packages--installing
      (progn
        ;; The in-flight install IS this tap's effect underway; the
        ;; toast is the render (S4's render-is-the-effect rule).
        (jetpacs-toast "Package install already in progress")
        'accepted)
    (jetpacs-toast "Installing packages…")
    (jetpacs-flow-continue
     (lambda ()
       (if (glasspane-packages-ensure)
           (jetpacs-toast "Packages ready — views refreshed")
         ;; The raw error text stays in *Messages*; the wire never
         ;; carries it (SPEC 23.3).
         (jetpacs-toast "Install failed — check *Messages* in Emacs"))))
    'accepted))

(defun glasspane-packages-register ()
  "Register the install verb and the Packages settings section.
Called from `glasspane-register', not at this file's load: the entry's
unregister must sweep every glasspane registration, and its re-register
must restore them without a re-require (the G0 gate contract)."
  (with-jetpacs-owner "glasspane"
    ;; Not v1's bare "packages.install": the v3 action table is GLOBAL
    ;; and the foundation package-browser owns that name
    ;; (jetpacs-package-browser.el) — every glasspane verb is
    ;; app-prefixed (the M3 convention G0 adopted).
    ;; No :any-surface: the not-installed empty states that carry this
    ;; tap (ef, srs) live on screens this owner pushed itself, and a
    ;; push onto a foreign surface registers the screen as a sanctioned
    ;; GUEST (`jetpacs-chrome-push-screen', S4) — the D1 gate then
    ;; admits the tap through `jetpacs-guest-delegation-function' for
    ;; exactly as long as that screen is on the stack.
    (jetpacs-defaction "glasspane.packages.install"
                       #'glasspane-packages--on-install
                       :doc "Install Glasspane's closed optional-engine set from MELPA")))

;; The auto-install row registers with the app's CONSOLIDATED
;; "Glasspane" section (glasspane-ui-register, §3 step 2): one app
;; block on the Settings root, not three orphan single-entry headers.

(defun glasspane-packages-unregister ()
  "Drop the install verb."
  (jetpacs-undefaction "glasspane.packages.install"))

;; v1's bundle entry made this call at its own load; requiring this
;; file IS that load moment, and every guard (interactive session,
;; store consent, something missing) lives inside.
(glasspane-packages-maybe-auto-install)

(provide 'glasspane-packages)
;;; glasspane-packages.el ends here
