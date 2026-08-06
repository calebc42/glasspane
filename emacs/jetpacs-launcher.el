;;; jetpacs-launcher.el --- Switch between app surfaces on the device -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JA-6's last surface (decision D-12: the launcher stays Emacs-side —
;; "apps are configs").  The reference Companion presents ONE app
;; surface at a time, last push wins, and nothing device-side switches
;; between them; this module is the switcher.  Its root lists every
;; surface with a registered builder (`jetpacs-shell-roots' — an app a
;; user could switch to is exactly a surface something would render),
;; and a row tap re-pushes that surface, which is what "switching"
;; means under last-write-wins.
;;
;; Reaching the launcher has the same shape as the problem it solves,
;; so `jetpacs.launcher.show' is a GLOBAL VERB (`:any-surface', the
;; theme-toggle precedent): any app may embed `jetpacs-launcher-button'
;; in its top bar, and the files browser does.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'subr-x)
(require 'jetpacs-chrome)

(defconst jetpacs-launcher-owner "jetpacs.launcher"
  "Owner string for the launcher surface (R1: base-reserved prefix).")

(defun jetpacs-launcher--entries ()
  "Switch targets as a sorted alist of (SURFACE . OWNER).
Every live root except the launcher's own; sorted by surface so the
list is stable across pushes."
  (sort (cl-remove-if
         (lambda (entry)
           (equal (car entry) (concat "app:" jetpacs-launcher-owner)))
         (jetpacs-shell-roots))
        (lambda (a b) (string< (car a) (car b)))))

(defvar jetpacs-launcher-row-icons nil
  "Alist of SURFACE (\"app:…\" form) -> icon name for switch rows.
Modules may seed their surface's icon; unlisted surfaces get \"apps\".")

(defvar jetpacs-launcher-row-labels nil
  "Alist of SURFACE (\"app:…\" form) -> display label for switch rows.
Modules seed these where the namespace-stripped `capitalize' guess is
wrong — initialisms, mostly: \"Sql\" must read \"SQL\".")

(defun jetpacs-launcher--pretty (owner surface)
  "A human title for a switch row: a seeded label, else the name sans
namespace, capitalized.  \"jetpacs.settings\" reads as \"Settings\"; an
unowned surface keeps its id (better an honest id than a wrongly
prettified one)."
  (or (cdr (assoc surface jetpacs-launcher-row-labels))
      (if owner
          (capitalize (string-remove-prefix "jetpacs." owner))
        surface)))

(defun jetpacs-launcher--row (surface owner)
  "One tappable row for SURFACE (registered by OWNER, maybe nil)."
  (jetpacs-chrome-row (jetpacs-launcher--pretty owner surface)
                      :icon (or (cdr (assoc surface
                                            jetpacs-launcher-row-icons))
                                "apps")
                      :subtitle (and owner surface)
                      :on-tap (jetpacs-action "jetpacs.launcher.open"
                                              :args (list :surface surface))
                      :key (jetpacs-wire-id "lr" surface)))

(defun jetpacs-launcher--view ()
  "The launcher root: a row per switchable app surface."
  (let ((entries (jetpacs-launcher--entries)))
    (if (null entries)
        (jetpacs-empty-state :icon "apps"
                             :title "Nothing to switch to"
                             :caption "No other app has registered a surface")
      (apply #'jetpacs-lazy-column
             (jetpacs-text "Apps" :style "title")
             (mapcar (lambda (entry)
                       (jetpacs-launcher--row (car entry) (cdr entry)))
                     entries)))))

(defun jetpacs-launcher-button ()
  "The top-bar affordance any app may embed to reach the launcher.
Under docs/CHROME-VOCABULARY.md the drawer is the canonical home for
app destinations — prefer embedding `jetpacs-launcher-rows' there; this
button remains for screens that have no drawer."
  (jetpacs-icon-button "apps"
                       (jetpacs-action "jetpacs.launcher.show")
                       :content-description "Apps"))

(defun jetpacs-launcher-rows (&optional exclude)
  "Destination rows for embedding in another app's drawer.
One row per switchable app surface — the drawer contract's app-level
destinations (docs/CHROME-VOCABULARY.md) — or a single empty-state.
EXCLUDE names one more surface to omit, canonically the embedder's own
\(its row would be a destination to where the user already is).  The
rows dispatch `jetpacs.launcher.open', a GLOBAL VERB, so they work
from any surface's drawer."
  (let ((entries (cl-remove-if (lambda (entry)
                                 (and exclude (equal (car entry) exclude)))
                               (jetpacs-launcher--entries))))
    (if (null entries)
        (list (jetpacs-empty-state
               :icon "apps"
               :title "Nothing to switch to"
               :caption "No other app has registered a surface"))
      (mapcar (lambda (entry)
                (jetpacs-launcher--row (car entry) (cdr entry)))
              entries))))

;;;; Actions and registration

(with-jetpacs-owner "jetpacs.launcher"

  (jetpacs-shell-define-root jetpacs-launcher-owner
                             #'jetpacs-launcher--view)

  (jetpacs-defaction "jetpacs.launcher.open"
    ;; The tapped row must still NAME a registered root: rows travel in
    ;; snapshots and a torn-down app can outlive its row on a cached
    ;; screen.  An unknown surface is `stale' — the snapshot is
    ;; outdated — never a push of whatever string arrived (the wire
    ;; does not get to nominate surfaces).
    (lambda (args params)
      (ignore params)
      (let ((target (plist-get args :surface)))
        (if (not (and (stringp target)
                      (assoc target (jetpacs-shell-roots))))
            'stale
          (jetpacs-flow-continue
           (lambda ()
             (condition-case err
                 (jetpacs-shell-push target)
               (error (message "jetpacs-launcher: switch failed: %s"
                               (jetpacs-error-label err))))))
          'accepted)))
    ;; A GLOBAL VERB since the drawer convention: `jetpacs-launcher-rows'
    ;; renders these descriptors inside other owners' drawers, so the
    ;; event's surface is legitimately foreign.  Safe under the exemption
    ;; because the membership guard above never pushes a surface the
    ;; registry does not name.
    :any-surface t)

  (jetpacs-defaction "jetpacs.launcher.show"
    ;; A GLOBAL VERB: the button renders in other owners' top bars, so
    ;; the event's surface is legitimately foreign (E2b's :any-surface
    ;; exemption, the theme-toggle precedent).
    (lambda (_args _params)
      (jetpacs-flow-continue
       (lambda ()
         (condition-case err
             (jetpacs-shell-push jetpacs-launcher-owner)
           (error (message "jetpacs-launcher: show failed: %s"
                           (jetpacs-error-label err))))))
      'accepted)
    :any-surface t))

;;;; Entry point and unload hygiene

(defun jetpacs-launcher ()
  "Push the launcher to the device now, loudly."
  (interactive)
  (jetpacs-client-or-error)
  (jetpacs-shell-push jetpacs-launcher-owner))

(defun jetpacs-launcher-unload-function ()
  "Unload hygiene: the owner's surface."
  (jetpacs-teardown-owner jetpacs-launcher-owner)
  nil)

(provide 'jetpacs-launcher)
;;; jetpacs-launcher.el ends here
