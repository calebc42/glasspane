;;; jetpacs-apps.el --- App identity over dock-as-data chrome -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; Groups owned surfaces into named apps, AppSheet-style, over the
;; chrome's dock-as-data seam (design: PLAN-poc1-parity, "The
;; app-identity design").  An app claims its surfaces and contributes
;; dock destinations in the exact `jetpacs-chrome-dock-items-function'
;; item shape; this module composes the seam, it never defines a second
;; vocabulary.
;;
;; The single-app contract (POC 1's, kept): with zero registered apps
;; the composed dock is byte-identical to the host-seeded core items;
;; with one app its destinations merge after core and nothing else
;; appears.  The launcher machinery — the Apps grid surface and the
;; trailing "Apps" destination — exists only from the second app on.
;;
;; THIS IS THE ENTRY POINT for a Tier 1 app:
;;
;;   1. Register your surfaces under (with-jetpacs-owner "<appid>" ...).
;;   2. Finish with `jetpacs-defapp' claiming them and declaring your
;;      dock destinations.
;;
;; One broken app costs its own destinations, never the dock: each
;; app's item builder runs under its own condition-case — the same
;; isolation the session-hook blanking bug taught.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)

(defconst jetpacs-apps-surface "jetpacs.apps"
  "The Apps grid's root surface (owner and surface name).")

(defvar jetpacs-apps-core-dock-items nil
  "The host's own dock destinations: a function (SURFACE) -> items.
Seeded by the device init (which used to set the chrome seam
directly); these render in EVERY app — the dock-as-data restatement of
POC 1's \"views not claimed by any app show everywhere\".")

(defvar jetpacs-apps--registry nil
  "Ordered alist of APP-ID -> plist (:label :icon :surfaces :dock :order).
:dock is a list of dock item plists or a function (SURFACE) -> items.")

(defvar jetpacs-apps--current nil
  "The current app's id, or nil before any `app.open'.")

;;;; Registry

(cl-defun jetpacs-defapp (id &key label icon surfaces dock (order 100))
  "Register (or replace) app ID.
LABEL and ICON draw its Apps-grid card; SURFACES is the list of surface
names it claims (the first is its home); DOCK is its destinations —
item plists in the chrome seam's shape, or a function of the surface.
Returns ID."
  (unless (and (stringp id) (not (string-empty-p id)))
    (error "jetpacs-defapp: id must be a non-empty string"))
  (setf (alist-get id jetpacs-apps--registry nil nil #'equal)
        (list :label (or label id) :icon (or icon "apps")
              :surfaces surfaces :dock dock :order order))
  (setq jetpacs-apps--registry
        (sort jetpacs-apps--registry
              (lambda (a b) (< (plist-get (cdr a) :order)
                               (plist-get (cdr b) :order)))))
  id)

(defun jetpacs-apps-unregister (id)
  "Remove app ID; the current app falls back to none."
  (setf (alist-get id jetpacs-apps--registry nil 'remove #'equal) nil)
  (when (equal jetpacs-apps--current id)
    (setq jetpacs-apps--current nil)))

(defun jetpacs-apps--multi-p ()
  (> (length jetpacs-apps--registry) 1))

(defun jetpacs-apps-current ()
  "The current app's registry entry (ID . PLIST), or nil.
Defaults to the sole registered app when only one exists."
  (or (and jetpacs-apps--current
           (assoc jetpacs-apps--current jetpacs-apps--registry))
      (and (= (length jetpacs-apps--registry) 1)
           (car jetpacs-apps--registry))))

(defun jetpacs-apps--home-surface (entry)
  (car (plist-get (cdr entry) :surfaces)))

;;;; The composed dock

(defun jetpacs-apps--app-items (entry surface)
  "ENTRY's dock destinations for SURFACE, isolated: a signal or a
malformed result costs this app's items only."
  (condition-case nil
      (let* ((dock (plist-get (cdr entry) :dock))
             (items (if (functionp dock) (funcall dock surface) dock)))
        (and (listp items)
             (cl-every (lambda (i) (and (listp i) (plist-get i :label)))
                       items)
             items))
    (error nil)))

(defun jetpacs-apps-dock-items (surface)
  "THE `jetpacs-chrome-dock-items-function': core + current app + Apps.
With fewer than two registered apps this composes to the core items
(plus the sole app's, when one exists) and nothing more — the
single-app contract."
  (append
   (when jetpacs-apps-core-dock-items
     (condition-case nil
         (funcall jetpacs-apps-core-dock-items surface)
       (error nil)))
   (when-let* ((entry (jetpacs-apps-current)))
     (jetpacs-apps--app-items entry surface))
   (when (jetpacs-apps--multi-p)
     (list (list :label "Apps" :icon "apps"
                 :on-tap (jetpacs-action "app.grid" :when-offline "drop")
                 :selected (equal surface
                                  (concat "app:" jetpacs-apps-surface)))))))

;;;; The Apps grid

(defun jetpacs-apps--card (entry)
  (pcase-let ((`(,id . ,plist) entry))
    (jetpacs-card
     (jetpacs-row
      (jetpacs-icon (plist-get plist :icon))
      (jetpacs-with-attrs
       (jetpacs-column
        (jetpacs-text (plist-get plist :label) :style "label")
        (jetpacs-text (or (jetpacs-apps--home-surface entry) "")
                      :style "caption"))
       :weight 1)
      (if (equal id (car (jetpacs-apps-current)))
          (jetpacs-icon "check_circle" :color "primary")
        (jetpacs-icon "chevron_right")))
     :on-tap (jetpacs-action "app.open" :args `(:app ,id)
                             :when-offline "drop"))))

(defun jetpacs-apps--view ()
  (apply #'jetpacs-lazy-column
         (cons (jetpacs-text "Apps" :style "title")
               (if (null jetpacs-apps--registry)
                   (list (jetpacs-empty-state
                          :icon "apps" :title "No apps registered"
                          :caption
                          "Apps appear here as their bundles load."))
                 (mapcar #'jetpacs-apps--card jetpacs-apps--registry)))))

;;;; Actions

(defun jetpacs-apps--action-grid (_args _params)
  (jetpacs-flow-continue
   (lambda ()
     (ignore-errors (jetpacs-shell-push jetpacs-apps-surface))))
  'accepted)

(defun jetpacs-apps--action-open (args _params)
  (let* ((id (plist-get args :app))
         (entry (and (stringp id) (assoc id jetpacs-apps--registry))))
    (if (null entry)
        'rejected
      (setq jetpacs-apps--current id)
      (let ((home (jetpacs-apps--home-surface entry)))
        (jetpacs-flow-continue
         (lambda ()
           (ignore-errors
             (jetpacs-shell-push (or home jetpacs-apps-surface))))))
      'accepted)))

(with-jetpacs-owner "jetpacs.apps"
  (jetpacs-shell-define-root jetpacs-apps-surface #'jetpacs-apps--view))
(jetpacs-defaction "app.grid" #'jetpacs-apps--action-grid)
(jetpacs-defaction "app.open" #'jetpacs-apps--action-open)

;; Install on the chrome seam.  The host seeds
;; `jetpacs-apps-core-dock-items' with what it used to put here
;; directly; anything else already on the seam is adopted as the core
;; builder rather than clobbered.
(when (and jetpacs-chrome-dock-items-function
           (not (eq jetpacs-chrome-dock-items-function
                    #'jetpacs-apps-dock-items))
           (null jetpacs-apps-core-dock-items))
  (setq jetpacs-apps-core-dock-items jetpacs-chrome-dock-items-function))
(setq jetpacs-chrome-dock-items-function #'jetpacs-apps-dock-items)

(provide 'jetpacs-apps)
;;; jetpacs-apps.el ends here