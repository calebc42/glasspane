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
  "Ordered alist of APP-ID -> plist
\(:label :icon :surfaces :dock :destinations :chrome :order).
:dock is a list of dock item plists or a function (SURFACE) -> items;
:destinations is the S1 route registry and :chrome the integration
pole — see `jetpacs-defapp'.")

(defvar jetpacs-apps--current nil
  "The current app's id, or nil before any `app.open'.")

(defvar jetpacs-apps--current-route nil
  "The current app's last-opened destination key, or nil.
Written only by `app.open' — set by a routed open, cleared by a plain
one — so the app-primary tabs can indicate the selected place (the
M3 navigation-bar contract).")

;;;; Registry

(defun jetpacs-apps--check-destination-list (dests)
  "Signal unless DESTS is a proper list of valid destinations; return it.
Each destination is a plist with string `:key' (a §4.4 identifier — it
rides `app.open''s wire args), string `:label', a DOTTED namespaced
`:verb' (the `jetpacs-action' rule: a dotless verb can never have a
registered handler, so every tap would silently degrade to the home
push), optional string `:icon'/`:subtitle'; keys distinct within the
app.  `proper-list-p' first: the reader trusts this checker to make a
resolved value safe to MAP, and a function or circular cell is not."
  (unless (proper-list-p dests)
    (error "jetpacs-defapp: :destinations must be a proper list, got %S"
           dests))
  (let (keys)
    (dolist (d dests)
      (unless (and (listp d) (keywordp (car-safe d)))
        (error "jetpacs-defapp: destination must be a plist, got %S" d))
      (jetpacs-check-identifier (plist-get d :key) "destination :key")
      (jetpacs-require-string (plist-get d :label) "destination :label")
      (let ((verb (plist-get d :verb)))
        (unless (and (jetpacs-identifier-p verb) (string-search "." verb))
          (error "jetpacs-defapp: destination :verb %S must be a §4.4 namespaced identifier containing a dot"
                 verb)))
      (when-let* ((icon (plist-get d :icon)))
        (jetpacs-check-identifier icon "destination :icon"))
      (when-let* ((sub (plist-get d :subtitle)))
        (jetpacs-require-string sub "destination :subtitle"))
      (when (member (plist-get d :key) keys)
        (error "jetpacs-defapp: duplicate destination key %S"
               (plist-get d :key)))
      (push (plist-get d :key) keys)))
  dests)

(defun jetpacs-apps--check-destinations (dests)
  "Signal unless DESTS is a valid `:destinations' value; return it.
A function is deferred trust (its RESULT is checked per read,
isolated, by `jetpacs-apps-destinations'); a list is checked NOW — the
build-time-validation house rule."
  (if (functionp dests)
      dests
    (jetpacs-apps--check-destination-list dests)))

(cl-defun jetpacs-defapp (id &key label icon surfaces dock destinations
                             chrome (order 100))
  "Register (or replace) app ID.
LABEL and ICON draw its Apps-grid card; SURFACES is the list of surface
names it claims (the first is its home); DOCK is its destinations —
item plists in the chrome seam's shape, or a function of the surface.

DESTINATIONS is the S1 route registry (CHROME-VOCABULARY v3, the
build-within pole; poc-1's `:views' restored onto chrome screens): a
list of plists (:key :label :verb [:icon :subtitle]) — or a function
of no arguments returning one — naming the screens the app offers the
HOST.  Each is opened via the global `app.open' with `:route KEY',
which re-dispatches the destination's VERB on the app's own home
surface — so the verb stays owner-scoped and no `:any-surface'
declaration is ever needed for a host-side row.

CHROME is the app's integration pole (CHROME-VOCABULARY v3):
nil (default) composes into the shell as today; `primary' makes the
dock APP-PRIMARY while this app is current — core collapses to its
first item, the app's DESTINATIONS become the tabs (through the same
`app.open' `:route' deep link), the Apps entry folds into the drawer;
`standalone' withdraws the core dock items and the global-actions
injection for the app's OWN surfaces and keeps the app's items off
foreign ones — the app authors its chrome whole.  Returns ID."
  (unless (and (stringp id) (not (string-empty-p id)))
    (error "jetpacs-defapp: id must be a non-empty string"))
  (unless (memq chrome '(nil standalone primary))
    (error "jetpacs-defapp: :chrome must be nil, standalone, or primary, got %S"
           chrome))
  (when destinations (jetpacs-apps--check-destinations destinations))
  (setf (alist-get id jetpacs-apps--registry nil nil #'equal)
        (list :label (or label id) :icon (or icon "apps")
              :surfaces surfaces :dock dock
              :destinations destinations :chrome chrome :order order))
  (setq jetpacs-apps--registry
        (sort jetpacs-apps--registry
              (lambda (a b) (< (plist-get (cdr a) :order)
                               (plist-get (cdr b) :order)))))
  id)

(defun jetpacs-apps-destinations (id)
  "App ID's destination list, resolved and isolated.
The function form is called here and its RESULT goes through the
LIST-ONLY checker — deferred trust is still checked trust, and a
function returning another function (or an improper list) must not
slip past a `functionp' fast path into a caller's `mapcar'.  A signal
or malformed value costs this app's destinations only, never a
caller."
  (when-let* ((entry (assoc id jetpacs-apps--registry)))
    (let ((dests (plist-get (cdr entry) :destinations)))
      (condition-case nil
          (jetpacs-apps--check-destination-list
           (if (functionp dests) (funcall dests) dests))
        (error nil)))))

(defun jetpacs-apps-unregister (id)
  "Remove app ID; the current app falls back to none."
  (setf (alist-get id jetpacs-apps--registry nil 'remove #'equal) nil)
  (when (equal jetpacs-apps--current id)
    (setq jetpacs-apps--current nil
          jetpacs-apps--current-route nil)))

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

(defun jetpacs-apps--entry-owns-surface-p (entry surface)
  "Non-nil when SURFACE (a full id) is one of ENTRY's claimed surfaces.
Colon-aware on both sides, mirroring the flow resolver."
  (cl-some (lambda (owner)
             (equal surface
                    (if (string-search ":" owner) owner
                      (jetpacs-shell-surface-for owner))))
           (plist-get (cdr entry) :surfaces)))

(defun jetpacs-apps-for-surface (surface)
  "The registry entry (ID . PLIST) of the app claiming SURFACE, or nil.
THE public identity read: the launcher takes a claimed surface's
label and icon from here — one enumeration, the registry — instead
of keeping a second vocabulary for surfaces that already have an
app.  Platform surfaces (not apps by owner decision) return nil and
keep their module-seeded launcher identity."
  (cl-loop for entry in jetpacs-apps--registry
           when (jetpacs-apps--entry-owns-surface-p entry surface)
           return entry))

(defun jetpacs-apps-home-for-surface (surface)
  "The registry entry (ID . PLIST) whose HOME surface is SURFACE, or nil.
The launcher's identity read: an entry names the APP, not the
surface, so only the app's home wears its label and icon — a claimed
SECONDARY surface (Org Mode claims the Files surface) keeps its own
platform identity.  Colon-aware like the ownership check."
  (cl-loop for entry in jetpacs-apps--registry
           for home = (jetpacs-apps--home-surface entry)
           ;; A registry SCAN, not a filter of the first ownership hit:
           ;; app A claiming SURFACE as a secondary must not shadow app
           ;; B whose home it is (registry order is :order, not claims).
           when (and home
                     (equal surface (if (string-search ":" home) home
                                      (jetpacs-shell-surface-for home))))
           return entry))

(defun jetpacs-apps--surface-chrome (surface)
  "The integration pole of the app owning SURFACE, or nil.
nil for host surfaces and for build-within apps alike — only a
declared pole changes composition."
  (plist-get (cdr (jetpacs-apps-for-surface surface)) :chrome))

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

(defun jetpacs-apps--destination-tabs (entry &optional limit)
  "ENTRY's destinations as dock tabs — the S2 app-primary form.
Each tab deep-links through the global `app.open' `:route' (the S1
mechanism powering S2), capped at LIMIT (four by default) so the host
core plus tabs stays inside the M3 five-item budget; `:selected'
follows the route this verb last opened."
  (pcase-let ((`(,id . ,_plist) entry))
    (mapcar (lambda (d)
              (list :label (plist-get d :label)
                    :icon (or (plist-get d :icon) "circle")
                    :on-tap (jetpacs-action
                             "app.open"
                             :args (list :app id
                                         :route (plist-get d :key))
                             :when-offline "drop")
                    :selected (and (equal id jetpacs-apps--current)
                                   (equal (plist-get d :key)
                                          jetpacs-apps--current-route))))
            (seq-take (jetpacs-apps-destinations id) (or limit 4)))))

(defun jetpacs-apps-dock-items (surface)
  "THE `jetpacs-chrome-dock-items-function', by integration pole.
Default (build-within, no declared pole): core + current app + Apps —
with fewer than two registered apps this composes to the core items
\(plus the sole app's, when one exists) and nothing more, the
single-app contract.  STANDALONE: on the app's own surfaces only its
authored `:dock' items ship (none authored: no dock at all — the app's
chrome is its own); on foreign surfaces a standalone current app
contributes NOTHING.  PRIMARY while current: core collapses to its
first item, the app's destinations become the tabs, and the Apps
entry folds into the drawer (`jetpacs-apps-drawer-row' already lives
there)."
  (let ((surface-pole (jetpacs-apps--surface-chrome surface))
        (entry (jetpacs-apps-current)))
    (cond
     ;; A standalone app's OWN surface: the app authors its chrome
     ;; whole (CHROME-VOCABULARY v3, the ratified withdrawal).
     ((eq surface-pole 'standalone)
      (and entry (jetpacs-apps--app-items entry surface)))
     ;; The current app is PRIMARY: global host destinations remain global;
     ;; its tabs fill the remaining slots in Material's five-item budget.
     ((and entry (eq (plist-get (cdr entry) :chrome) 'primary))
      (let* ((core (when jetpacs-apps-core-dock-items
                     (condition-case nil
                         (funcall jetpacs-apps-core-dock-items surface)
                       (error nil))))
             (room (max 0 (- 5 (length core)))))
        (append core (jetpacs-apps--destination-tabs entry room))))
     ;; Build-within default.
     (t
      (append
       (when jetpacs-apps-core-dock-items
         (condition-case nil
             (funcall jetpacs-apps-core-dock-items surface)
           (error nil)))
       ;; A standalone CURRENT app keeps its items off foreign
       ;; surfaces — they are its own chrome, not a contribution.
       (when (and entry
                  (not (eq (plist-get (cdr entry) :chrome) 'standalone)))
         (jetpacs-apps--app-items entry surface))
       (when (jetpacs-apps--multi-p)
         (list (list :label "Apps" :icon "apps"
                     ;; Use the same guarded global switch verb as the
                     ;; drawer.  The retired app.grid wrapper swallowed push
                     ;; failures and produced a visibly dead destination.
                     :on-tap (jetpacs-action
                              "jetpacs.launcher.open"
                              :args '(:surface "app:jetpacs.app-store")
                              :when-offline "drop")
                     :selected (equal surface
                                      "app:jetpacs.app-store")))))))))

;;;; The global-actions wrapper (S3, standalone-aware)

(defvar jetpacs-apps-core-global-actions nil
  "The host's shell-global top-bar actions: a function (SURFACE) -> nodes.
Seeded by the device init (M-x, canonically); rendered into every
screen through `jetpacs-chrome-global-actions-function' — except on a
standalone app's surfaces, where the ratified withdrawal applies.")

(defun jetpacs-apps-global-actions (surface)
  "THE `jetpacs-chrome-global-actions-function': the host seed, minus
standalone surfaces (CHROME-VOCABULARY v3: `:chrome' `standalone'
withdraws the global-actions injection for the app's own surfaces)."
  (unless (eq (jetpacs-apps--surface-chrome surface) 'standalone)
    (when jetpacs-apps-core-global-actions
      (condition-case nil
          (funcall jetpacs-apps-core-global-actions surface)
        (error nil)))))

;;;; The composed drawer (S8, standalone-aware)

(defvar jetpacs-apps-core-drawer-rows nil
  "The host's own drawer rows: a function (SURFACE) -> a list of nodes.
Seeded by the device init (the Tools nest, the divider, and the
Settings nest, canonically — the pass-4 IA tail); composed BELOW the
app-identity head — the Apps row and the destination nests — by
`jetpacs-apps-drawer'.  Isolated: a signal or a non-list costs the
host rows, never the drawer.")

(defun jetpacs-apps-drawer (surface)
  "THE `jetpacs-chrome-drawer-function': the composed host drawer.
The head is the app-identity half — the Apps entry and one S1
destination nest per registered app — and the tail is the host's own
rows (`jetpacs-apps-core-drawer-rows').  On the hub this composes
exactly the drawer its root used to author by hand; on every other
build-within root it is the SAME drawer, which is the point — the
canonical navigation list no longer depends on which screen the user
is standing on.  STANDALONE withdraws whole: the app authors its
chrome, drawer included (CHROME-VOCABULARY v3)."
  (unless (eq (jetpacs-apps--surface-chrome surface) 'standalone)
    (apply #'jetpacs-lazy-column
           (append
            (list (jetpacs-apps-drawer-row))
            (jetpacs-apps-destination-rows)
            (when jetpacs-apps-core-drawer-rows
              (condition-case nil
                  (let ((rows (funcall jetpacs-apps-core-drawer-rows
                                       surface)))
                    (and (listp rows) (cl-every #'jetpacs-node-p rows)
                         rows))
                (error nil)))
            (list :spacing 8)))))

;;;; The Apps grid

(defun jetpacs-apps--card (entry)
  (pcase-let ((`(,id . ,plist) entry))
    (jetpacs-chrome-row (plist-get plist :label)
                        :subtitle (jetpacs-apps--home-surface entry)
                        :icon (plist-get plist :icon)
                        :trailing (if (equal id (car (jetpacs-apps-current)))
                                      (jetpacs-icon "check_circle"
                                                    :color "primary")
                                    (jetpacs-icon "chevron_right"))
                        :on-tap (jetpacs-action "app.open" :args `(:app ,id)
                                                :when-offline "drop")
                        :key (jetpacs-wire-id "ap" id))))

(defun jetpacs-apps--view ()
  (jetpacs-chrome-screen
   "Apps"
   (apply #'jetpacs-lazy-column
          (if (null jetpacs-apps--registry)
              (list (jetpacs-empty-state
                     :icon "apps" :title "No apps registered"
                     :caption "Apps appear here as their bundles load."))
            (mapcar #'jetpacs-apps--card jetpacs-apps--registry)))))

;;;; The drawer's Apps entry

(defun jetpacs-apps-drawer-row ()
  "The drawer's single Apps entry (owner decision 2026-08-06 pass 2):
one plain row opening the combined Apps view, where installing,
removing, editing, and launching all live.  An App is a Tier 1 elisp
package built ON jetpacs — platform surfaces are not apps and are not
listed there."
  (jetpacs-chrome-row "Apps"
                      :subtitle "Install, manage, and launch"
                      :icon "apps"
                      :on-tap (jetpacs-action
                               "jetpacs.launcher.open"
                               :args '(:surface "app:jetpacs.app-store"))
                      :key "drawer-apps"))

(defun jetpacs-apps--destination-row (id dest)
  "One host-drawer row for app ID's destination DEST.
The tap is the global `app.open' with the route — never the
destination's own verb, which is owner-scoped and would be refused on
the host surface (the S1 point)."
  (jetpacs-chrome-row (plist-get dest :label)
                      :subtitle (plist-get dest :subtitle)
                      :icon (or (plist-get dest :icon) "chevron_right")
                      :on-tap (jetpacs-action
                               "app.open"
                               :args (list :app id
                                           :route (plist-get dest :key))
                               :when-offline "drop")
                      :key (jetpacs-wire-id
                            "apd" (concat id "/" (plist-get dest :key)))))

(defun jetpacs-apps-destination-rows ()
  "Every registered app's destinations as host-drawer nests.
The S1 consumption seam (CHROME-VOCABULARY v3, build-within): the HOST
composes what apps CONTRIBUTE — poc-1's claimed-views drawer restored.
One collapsible per app that declares destinations (collapsed by
default, the settings-nest precedent — a plain row header so the whole
line is the expand target); apps without them cost nothing, and a
broken destination list costs that app's nest alone
\(`jetpacs-apps-destinations' isolates)."
  (delq nil
        (mapcar
         (lambda (entry)
           (pcase-let ((`(,id . ,plist) entry))
             (when-let* ((dests (jetpacs-apps-destinations id)))
               (apply #'jetpacs-collapsible
                      (jetpacs-wire-id "apn" id)
                      (jetpacs-row
                       (jetpacs-icon (plist-get plist :icon))
                       (jetpacs-with-attrs
                        (jetpacs-text (plist-get plist :label))
                        :weight 1))
                      (append
                       (mapcar (lambda (d)
                                 (jetpacs-apps--destination-row id d))
                               dests)
                       ;; Collapsed by default — the settings/tools
                       ;; nest precedent, EXPLICIT: collapsible's own
                       ;; default is expanded.
                       (list :collapsed t))))))
         jetpacs-apps--registry)))

;;;; Actions

(defun jetpacs-apps--action-grid (_args _params)
  ;; The dock's Apps destination lands on the combined Apps view (the
  ;; app-store surface) — the grid folded into it (pass 2).
  (jetpacs-flow-continue
   (lambda ()
     (ignore-errors (jetpacs-shell-push "jetpacs.app-store"))))
  'accepted)

(defun jetpacs-apps--action-open (args _params)
  "Open app `:app'; with `:route', open one of its DESTINATIONS.
The S1 deep link: the tapping row lives on a HOST surface the app does
not own, but this verb is ownerless (gate-exempt), and the route's
verb is re-dispatched through `jetpacs--dispatch' with the app's OWN
home surface as the event surface — the D1 gate passes because the
context is genuinely the app's, which is what retires the
`:any-surface' workaround for host-side rows.  A vanished route is
`stale' (the row outlived the registry it was rendered from); the
route's own status is adopted with a plain home push as the fallback
when it refused — the app still opens."
  (let* ((id (plist-get args :app))
         (entry (and (stringp id) (assoc id jetpacs-apps--registry)))
         (route (plist-get args :route)))
    (cond
     ((null entry) 'rejected)
     ((and route (not (stringp route))) 'rejected)
     (t
      (let* ((dest (and route
                        (cl-find route (jetpacs-apps-destinations id)
                                 :key (lambda (d) (plist-get d :key))
                                 :test #'equal)))
             (home (jetpacs-apps--home-surface entry)))
        (if (and route (null dest))
            'stale
          (setq jetpacs-apps--current id
                jetpacs-apps--current-route (and dest route))
          (jetpacs-flow-continue
           (lambda ()
             (if-let* ((verb (and dest (plist-get dest :verb)))
                       (handler (gethash verb jetpacs-action-handlers))
                       ;; Colon-aware, mirroring the flow resolver: a
                       ;; `:surfaces' entry is normally an owner name,
                       ;; but a full surface id must not grow a second
                       ;; prefix.
                       (surface (and home
                                     (if (string-search ":" home) home
                                       (jetpacs-shell-surface-for home)))))
                 ;; The full dispatch discipline — owner binding, the
                 ;; D1 gate, prompt pinning — AND the flow identity:
                 ;; the continuation inherited the HOST's device flow,
                 ;; and `jetpacs-flow-surface' prefers the flow over
                 ;; dispatch params, so without this rebinding a
                 ;; destination verb written against the navigate/flow
                 ;; patterns would drill onto the host surface — the
                 ;; exact foreign act the gate exists to refuse, done
                 ;; with its approval.  A direct `let', not
                 ;; `jetpacs--call-with-flow': that helper refuses a
                 ;; nested different-surface flow BY DESIGN, and this
                 ;; is the one sanctioned hand-off from the host's
                 ;; flow to the app's.  Client nil — a local
                 ;; re-dispatch, no wire reply.  The condition-case is
                 ;; load-bearing: `jetpacs--dispatch' deliberately
                 ;; RE-SIGNALS typed jsonrpc errors (the wire-reply
                 ;; path's contract), but here there is no wire — an
                 ;; escaping `jetpacs-retry-later' or 1500 would die
                 ;; in the timer with the fallback skipped and the
                 ;; intent silently lost.
                 (unless (eq (condition-case nil
                                 (let ((jetpacs--device-flow
                                        (list :surface surface
                                              :owner (jetpacs--owner-of
                                                      "action" verb))))
                                   (jetpacs--dispatch
                                    nil (list :action verb :surface surface)
                                    handler))
                               (error 'rejected))
                             'accepted)
                   (ignore-errors
                     (jetpacs-shell-push (or home "jetpacs.app-store"))))
               (ignore-errors
                 (jetpacs-shell-push (or home "jetpacs.app-store"))))))
          'accepted))))))

;; No root of its own (pass 2): the grid folded into the combined Apps
;; view on the app-store surface; `jetpacs-apps--card' renders there.
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
;; The S3 seam installs the same way: adopt any pre-existing raw
;; function as the core seed, then wrap it standalone-aware.
(when (and jetpacs-chrome-global-actions-function
           (not (eq jetpacs-chrome-global-actions-function
                    #'jetpacs-apps-global-actions))
           (null jetpacs-apps-core-global-actions))
  (setq jetpacs-apps-core-global-actions
        jetpacs-chrome-global-actions-function))
(setq jetpacs-chrome-global-actions-function #'jetpacs-apps-global-actions)
;; The S8 seam installs plainly: it is born alongside this composition,
;; so unlike the two above there is no pre-existing direct setter to
;; adopt — the host seeds `jetpacs-apps-core-drawer-rows' instead
;; (defvar-before-load, the core-global-actions pattern).
(setq jetpacs-chrome-drawer-function #'jetpacs-apps-drawer)

(provide 'jetpacs-apps)
;;; jetpacs-apps.el ends here
