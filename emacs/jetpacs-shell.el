;;; jetpacs-shell.el --- The surface push path over ebp.el -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The application-framework floor's push half (rung JC-0 of
;; docs/PLAN-jetpacs-consumers.md; build spec docs/SPEC-JC-0-floor.md):
;; `jetpacs-shell-push' over `ebp-client-surface-update', carrying the
;; runtime gates the builders cannot enforce (spec plan section 2.5):
;;
;;   GATE 1  SPEC 16.2 + 10.2 — node types and builtins validated against
;;           the LIVE welcome profile, never the reference defconst.
;;   GATE 2  SPEC 13.4/13.5 — `current_view' only for a multi-view spec;
;;           `stale_spec' same variant, stateful nodes and editors stripped.
;;   GATE 3  SPEC 13.1 — notification:/widget:/tile: pushes require the
;;           granted surface capability; ebp does not enforce this.
;;   GATE 4  amendments #85/#84 — no `wake' descriptor without the
;;           `offline.wake' grant; no synchronized editor whose document
;;           exceeds `max_editor_bytes'.
;;
;; Decision D1 (spec section 0): surfaces are per-owner, `app:<owner>'.
;; The optional first argument of `jetpacs-shell-push' names either a
;; full surface id (contains a colon) or a bare owner; zero-arg re-renders
;; the current owner's surface, else `jetpacs-shell-surface-id'.
;; `jetpacs-async--flush-push' calls `(jetpacs-shell-push OWNER)'.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-async)

(defvar jetpacs-buffer-refresh-function) ; jetpacs-buffer.el (JC-1)

(defvar jetpacs-shell-surface-id "app:main"
  "Default surface for an ownerless zero-arg push (SPEC 13.4 app:*).")

(defvar jetpacs-shell--roots nil
  "Alist SURFACE -> plist (:builder FN :owner ID :required BOOL
:stale-after-s N :stale-builder FN).  One single-root entry per surface.")

(defvar jetpacs-shell-after-push-hook nil
  "Normal hook run synchronously after a successful send.
Runs after `ebp-client-surface-update' returned its claimed revision —
not from the async result callback.  Carries the `jetpacs-async'
generation sweep.")

(defvar jetpacs-shell-refresh-hook nil
  "Normal hook run before a cache-bypassing push; drop memo caches here.")

(defvar jetpacs-shell--snackbar nil
  "One-slot queued snackbar text for the next push; latest wins.")

(defvar jetpacs-shell--repush-pending nil
  "Surfaces awaiting the debounced registry repush.")

(defvar jetpacs-shell--pending-removals nil
  "Surfaces whose tombstone could not be sent while disconnected.
Flushed at the next Section 10.3 barrier; without this a removal made
offline is lost and the surface stays present forever (SPEC 4.5
`max_surfaces').")

(defvar jetpacs-shell--repush-timer nil
  "The idle timer draining `jetpacs-shell--repush-pending'.")

(defvar jetpacs-shell--in-barrier nil
  "Non-nil during the SPEC 10.3 step-3 required-root push, where the
session is still `syncing' and the READY guard must not apply.")

(defconst jetpacs-shell--frame-headroom 2048
  "Octets GATE 5 reserves from `max_frame_bytes' for the envelope.")

(defconst jetpacs-shell--max-node-depth 20
  "SPEC 4.5 fixed `max_node_depth' (contract limits.fixed).")

(defconst jetpacs-shell--stateful-types
  '("text_input" "checkbox" "switch" "enum_list" "slider" "editor")
  "Node types `jetpacs-shell--strip-stateful' removes from a stale_spec.
SPEC 13.5: no stateful node and no `editor' regardless of publish_state.")

;;;; Surface naming (decision D1)

(defun jetpacs-shell-surface-for (owner)
  "The D1 surface id for OWNER: `app:<owner>'."
  (concat "app:" owner))

(defun jetpacs-shell--resolve-surface (surface-or-owner)
  "Resolve SURFACE-OR-OWNER to a surface id.
nil -> the current owner's surface, else `jetpacs-shell-surface-id'.
A string with a colon is already a surface id; one without is a D1
owner and maps to `app:<owner>'."
  (cond
   ((null surface-or-owner)
    (if jetpacs-current-owner
        (jetpacs-shell-surface-for jetpacs-current-owner)
      jetpacs-shell-surface-id))
   ((string-search ":" surface-or-owner) surface-or-owner)
   (t (jetpacs-shell-surface-for surface-or-owner))))

(defun jetpacs-shell--surface-target (surface)
  "SURFACE's profile key: :app / :notification / :widget / :tile (SPEC 10.2)."
  (pcase (car (split-string surface ":"))
    ("app" :app)
    ("notification" :notification)
    ("widget" :widget)
    ("tile" :tile)
    (prefix (error "jetpacs: unknown surface namespace %S (SPEC 13.1)"
                   prefix))))

;;;; Root registry

(cl-defun jetpacs-shell-define-root (surface builder &key required
                                             stale-after-s stale-builder)
  "Register BUILDER (nullary -> root Node or SurfaceSpec) for SURFACE.
SURFACE takes the `jetpacs-shell--resolve-surface' forms (a bare owner
names `app:<owner>').  REQUIRED roots are re-pushed on reconnect before
`queue.replay' (SPEC 10.3 step 3).  Replaces an existing entry;
schedules a debounced repush on a live session.  Returns SURFACE."
  (let ((surface (jetpacs-shell--resolve-surface surface)))
    (jetpacs--claim "surface" surface)
    (setf (alist-get surface jetpacs-shell--roots nil nil #'equal)
          (list :builder builder :owner jetpacs-current-owner
                :required required :stale-after-s stale-after-s
                :stale-builder stale-builder))
    (jetpacs-shell--schedule-repush surface)
    surface))

(defun jetpacs-shell-remove-root (surface)
  "Unregister SURFACE's root and tombstone it (SPEC 13.3).
A removal requested while disconnected is REMEMBERED, not dropped: the
registry entry is gone, so nothing would ever re-push or retire the
surface, and it would sit present against `max_surfaces' (SPEC 4.5)
until the pairing was revoked.  The pending tombstone is issued at the
next Section 10.3 barrier."
  (let ((surface (jetpacs-shell--resolve-surface surface)))
    (setf (alist-get surface jetpacs-shell--roots nil 'remove #'equal) nil)
    (jetpacs--unclaim "surface" surface)
    (setq jetpacs-shell--repush-pending
          (delete surface jetpacs-shell--repush-pending))
    (if (jetpacs-connected-p)
        (jetpacs-shell--send-remove surface)
      (cl-pushnew surface jetpacs-shell--pending-removals :test #'equal))))

(defun jetpacs-shell--send-remove (surface)
  "Send SURFACE's tombstone with loss-proofing; returns the revision.
The bare send this replaces passed NO callback, so a tombstone the W10
sender ceiling refused — concluded locally and synchronously with 1401,
never touching the wire — was silently LOST, and the surface sat
present against `max_surfaces' until revocation.  Any error (refusal,
timeout, transport loss) now requeues the removal for the next SPEC
10.3 barrier; `cl-pushnew' makes the synchronous-refusal push during
this very call harmless."
  (ebp-client-surface-remove
   (jetpacs-client) surface
   :callback
   (lambda (_status error)
     (when error
       (cl-pushnew surface jetpacs-shell--pending-removals :test #'equal)
       (message "jetpacs: surface.remove of %s failed (code %s, %s); queued for the next barrier"
                surface (plist-get error :code)
                (or (plist-get (plist-get error :data) :kind) "?"))))))

(defvar jetpacs-shell--current-view)    ; defined with the view machinery

(defun jetpacs-shell--owner-surfaces (owner)
  "OWNER's D1 primary surface plus every surface claimed under it."
  (cl-remove-duplicates
   (cons (jetpacs-shell-surface-for owner)
         (jetpacs--owned-names "surface" owner))
   :test #'equal))

(defun jetpacs-teardown-owner (owner)
  "Tear down everything attributed to OWNER (G5); returns OWNER.
The live-reload verb: under D1 every redefinition without this leaves a
visible orphaned surface on the device.  Sweeps, in load-bearing order
— local registries FIRST, wire LAST, so a debounced repush firing
re-entrantly inside a blocked send finds no root and no-ops instead of
resurrecting the surface above its tombstone: actions (the dispatch
shim then rejects racing events), async loaders (a late settle is
inert), then per surface: state subscriptions before the wire call,
the tombstone itself, then the applied-revision and current-view
residue.  Wire failures requeue for the next barrier and never signal;
a second call is an idempotent cheap no-op.

Scope notes: registrations made OUTSIDE `with-jetpacs-owner' carry no
attribution and are not swept.  Tombstones persist until revocation
(SPEC 13.3) — which is why a surface the client cannot know about
(never pushed, no revision floor) gets a local unclaim only, never a
gratuitous permanent tombstone.  An in-flight bridged dialog is NOT
cancelled: it is unattributed single-flight, and its continuation
degrades safely (a rootless push returns nil, its re-armed actions are
already gone).  ebp's input-draft mirror keeps the removed surface's
drafts until the Companion republishes — pass `:reset-input-ids' on a
re-registering push when that matters."
  (interactive (list (completing-read "Tear down owner: "
                                      (jetpacs--owners) nil t)))
  (unless (jetpacs--valid-owner-p owner)
    (error "jetpacs: invalid owner %S (a D1 owner name, not a surface id)"
           owner))
  (dolist (name (jetpacs--owned-names "action" owner))
    (jetpacs-undefaction name))
  (jetpacs-async-clear-owner owner)
  (let ((client (jetpacs-client)))
    (dolist (surface (jetpacs-shell--owner-surfaces owner))
      (jetpacs-on-state-change-clear "" surface)
      (if (or (alist-get surface jetpacs-shell--roots nil nil #'equal)
              (and client
                   (gethash surface (ebp-client-revisions client))))
          (jetpacs-shell-remove-root surface)
        (jetpacs--unclaim "surface" surface))
      (remhash surface jetpacs--applied-revisions)
      (remhash surface jetpacs-shell--current-view)))
  (dolist (fn jetpacs-teardown-functions)
    (condition-case err
        (funcall fn owner)
      (error (message "jetpacs: teardown hook failed: %s"
                      (jetpacs--error-label err)))))
  owner)

(defun jetpacs-shell--schedule-repush (surface)
  "Debounce a repush of SURFACE after a registry mutation (0.5 s idle).
No-op while disconnected: the reconnect barrier push carries the
registrations."
  (when (jetpacs-connected-p)
    (cl-pushnew surface jetpacs-shell--repush-pending :test #'equal)
    (unless (timerp jetpacs-shell--repush-timer)
      (setq jetpacs-shell--repush-timer
            (run-with-idle-timer
             0.5 nil
             (lambda ()
               (setq jetpacs-shell--repush-timer nil)
               (let ((surfaces (nreverse jetpacs-shell--repush-pending)))
                 (setq jetpacs-shell--repush-pending nil)
                 (dolist (s surfaces) (jetpacs-shell-push s)))))))))

(defun jetpacs-shell--on-ready (_client)
  "Drain pushes that SYNCING refused, now that the session is READY.
Installed by `jetpacs-connect'.  Replayed events conclude before
`session.ready' (SPEC 10.3 step 4 precedes step 5), so every effect
push a replayed handler deferred has already been queued by the time
this runs; each drained push re-renders the CURRENT state through the
registered builder, so collapsed duplicates are harmless."
  (let ((surfaces (nreverse jetpacs-shell--repush-pending)))
    (setq jetpacs-shell--repush-pending nil)
    (dolist (s surfaces)
      (condition-case err
          (jetpacs-shell-push s)
        (error (message "jetpacs: READY drain push of %s failed: %s"
                        s (jetpacs--error-label err)))))))

(defun jetpacs-shell--drop-pending (surface)
  "Forget SURFACE's queued repush; stop the timer once nothing is queued.
Per surface: an explicit push of one owner's surface satisfies only its
OWN queued repush — clearing the whole queue would silently drop every
other owner's pending re-render (decision D1 makes that routine)."
  (setq jetpacs-shell--repush-pending
        (delete surface jetpacs-shell--repush-pending))
  (when (and (null jetpacs-shell--repush-pending)
             (timerp jetpacs-shell--repush-timer))
    (cancel-timer jetpacs-shell--repush-timer)
    (setq jetpacs-shell--repush-timer nil)))

;;;; Building (degrade in place: the live-coding contract)

(defun jetpacs-shell--error-spec (surface message detail)
  "A visible error view shaped for SURFACE's SPEC 13.4 variant.
A bare Node is a valid spec only for `app:*'; emitting one for a
`notification:'/`widget:' surface would make the degrade path itself
content-invalid, so the error view could never appear exactly where a
builder crashed."
  (let ((node (jetpacs-column
               (jetpacs-text message :style "title")
               (jetpacs-text detail :style "body"))))
    (pcase (jetpacs-shell--surface-target surface)
      (:notification (jetpacs-notification-surface node))
      (:widget (jetpacs-widget-surface "Error" node))
      (_ node))))

(defun jetpacs-shell--build (surface plist)
  "Call SURFACE's :builder from PLIST; a crash degrades to an error view.
A broken builder costs its own screen, never the whole push.  The
builder runs under its registered owner, so `jetpacs-ui-state' and any
other owner-scoped lookup resolve to the surface being built — a
repush or async flush carries no ambient owner of its own."
  (condition-case err
      ;; The inherit is for a DESKTOP Lisp caller pushing from inside its
      ;; own `with-jetpacs-owner'.  It must NOT cross a dispatch: with the
      ;; owner now bound there, building an OWNERLESS root from inside an
      ;; owned handler would run the builder under the handler's owner,
      ;; and a zero-arg `jetpacs-shell-push' or `jetpacs-ui-state' inside
      ;; it would silently read and write another surface's SPEC 14.6
      ;; input store.
      (let ((jetpacs-current-owner
             (or (plist-get plist :owner)
                 (and (not jetpacs--in-action-handler)
                      jetpacs-current-owner))))
        (funcall (plist-get plist :builder)))
    (error
     (jetpacs-shell--error-spec surface
                                (format "Error building %s" surface)
                                (error-message-string err)))))

;;;; Spec walkers (the `jetpacs--opaque-members' discipline: never descend
;;;; into :args/:meta/:value, so application data is never misread)

(defun jetpacs-shell--walk-plists (value fn)
  "Call FN on every keyword plist in VALUE, skipping opaque members."
  (cond
   ((vectorp value)
    (mapc (lambda (v) (jetpacs-shell--walk-plists v fn)) value))
   ((hash-table-p value)
    (maphash (lambda (_k v) (jetpacs-shell--walk-plists v fn)) value))
   ((and (consp value) (keywordp (car value)))
    (funcall fn value)
    (let ((p value))
      (while p
        (let ((k (pop p)) (v (pop p)))
          (unless (memq k jetpacs--opaque-members)
            (jetpacs-shell--walk-plists v fn))))))
   ((consp value)
    (dolist (v value) (jetpacs-shell--walk-plists v fn)))))

(defun jetpacs-shell--check-builtins (spec allowed what)
  "GATE 1b, SPEC 10.2: every builtin in SPEC must be advertised.
ALLOWED is the profile's builtins coerced to a list; WHAT names the
target for the message."
  (jetpacs-shell--walk-plists
   spec
   (lambda (p)
     (when-let* ((builtin (plist-get p :builtin)))
       (unless (member builtin allowed)
         (error "jetpacs: builtin %S is not advertised for %s (SPEC 10.2)"
                builtin what))))))

(defun jetpacs-shell--meta-descriptors (spec)
  "Every ActionDescriptor hiding inside SPEC's `:meta' (SPEC 18.5).
`jetpacs--opaque-members' skips `:meta' because a chart point's `meta'
is opaque application data — but a `notification:*' SurfaceSpec puts its
18.5 metadata under the SAME key, and that metadata carries
`actions[].on_tap' descriptors.  The generic walker is therefore blind
to exactly the descriptors amendment #85 exists to gate, so the gates
call this to reach them."
  (let (found)
    (seq-doseq (entry (or (plist-get (plist-get spec :meta) :actions) []))
      (when-let* ((tap (plist-get entry :on_tap)))
        (push tap found)))
    found))

(defun jetpacs-shell--check-features (spec allowed what)
  "GATE 1c, SPEC 10.2: every constraining feature in SPEC is advertised.
10.2 mandates gating nodes, builtins, AND features; the SPEC names
exactly two constraining feature families — `image.https'/`image.data'
\(17.2) and `toolbar.<identifier>' (17.7).  There is no feature registry
to enumerate beyond them (see the audit's SPEC finding 9), so this
gate is deliberately keyed to those two."
  (jetpacs-shell--walk-plists
   spec
   (lambda (p)
     (pcase (plist-get p :t)
       ("image"
        (let* ((url (plist-get p :url))
               (need (and (stringp url)
                          (if (string-prefix-p "data:" url)
                              "image.data"
                            "image.https"))))
          (when (and need (not (member need allowed)))
            (error "jetpacs: image URI form needs the unadvertised \
feature %S for %s (SPEC 17.2)" need what))))
       ("editor"
        (let ((toolbar (plist-get p :toolbar)))
          ;; An inline ToolbarItem array is a vector and needs no feature;
          ;; only a REGISTERED identifier (a string) does.
          (when (stringp toolbar)
            (let ((need (concat "toolbar." toolbar)))
              (unless (member need allowed)
                (error "jetpacs: editor toolbar %S needs the unadvertised \
feature %S for %s (SPEC 17.7)" toolbar need what))))))))))

(defun jetpacs-shell--strip-stateful (value)
  "A copy of VALUE with every stateful node and editor removed (SPEC 13.5).
Opaque members pass through untouched; a member whose node was stripped
is omitted; stripped children vanish from their sequences."
  (cond
   ((vectorp value)
    (vconcat (delq nil (mapcar #'jetpacs-shell--strip-stateful
                               (append value nil)))))
   ((hash-table-p value)
    (let ((h (make-hash-table :test (hash-table-test value))))
      (maphash (lambda (k v)
                 (when-let* ((sv (jetpacs-shell--strip-stateful v)))
                   (puthash k sv h)))
               value)
      h))
   ((and (consp value) (keywordp (car value)))
    (if (member (plist-get value :t) jetpacs-shell--stateful-types)
        nil
      (let ((p value) out)
        (while p
          (let* ((k (pop p)) (v (pop p))
                 (sv (if (memq k jetpacs--opaque-members)
                         v
                       (jetpacs-shell--strip-stateful v))))
            (when (or sv (null v))       ; keep an authored nil/false as-is
              (setq out (nconc out (list k sv))))))
        out)))
   ((consp value)
    (delq nil (mapcar #'jetpacs-shell--strip-stateful value)))
   (t value)))

(defun jetpacs-shell--validate-stripped (original stripped)
  "STRIPPED (the 13.5 strip of ORIGINAL) if it is still a valid
SurfaceSpec, else signal; nil when nothing survived.
Stripping removes members and hash entries, so it can quietly destroy
the SurfaceSpec's own required shape (SPEC 13.4): a widget losing its
REQUIRED `body', or a multi-view whose `initial_view' now names no
surviving view.  Either ships content-invalid, and per 13.2 the
Companion rejects the ENTIRE request — discarding the valid primary
`spec' with it and leaving the previous snapshot.  A sender MUST is
loud, so this signals rather than sanitizing further."
  (cond
   ((null stripped)
    ;; A wholly-stateful stale root strips to nothing; say so rather than
    ;; silently pushing with no stale view at all.
    (display-warning
     'jetpacs "stale_spec was entirely stateful (SPEC 13.5); dropped"
     :warning)
    nil)
   ((and (plist-member original :body) (null (plist-get stripped :body)))
    (error "jetpacs: stale_spec lost its REQUIRED `body' to the 13.5 \
stateful strip (SPEC 13.4)"))
   ((and (plist-get stripped :views)
         (not (gethash (plist-get stripped :initial_view)
                       (plist-get stripped :views))))
    (error "jetpacs: stale_spec `initial_view' %S names no surviving view \
after the 13.5 stateful strip (SPEC 13.4)"
           (plist-get stripped :initial_view)))
   (t stripped)))

;;;; The gates

(defun jetpacs-shell--gate-spec (client surface spec stale-spec)
  "GATE 1: SPEC 16.2 node types + SPEC 10.2 builtins, against the LIVE
welcome profile — never `jetpacs-check-profile''s reference defconst.
Signals; never sanitizes (a sender MUST is loud)."
  (let* ((target (jetpacs-shell--surface-target surface))
         (profile (plist-get (ebp-client-profiles client) target))
         (what (substring (symbol-name target) 1)))
    ;; SPEC 10.2: a missing profile or list is NOT support for everything.
    (unless profile
      (error "jetpacs: no %s surface profile advertised (SPEC 10.2)" what))
    ;; jsonrpc decodes arrays as vectors; jetpacs-check-node-types uses
    ;; `member', so the coercion is mandatory.
    (let ((types (append (plist-get profile :node_types) nil))
          (builtins (append (plist-get profile :builtins) nil))
          (features (append (plist-get profile :features) nil)))
      (dolist (s (delq nil (list spec stale-spec)))
        (jetpacs-check-node-types s types what)
        (jetpacs-shell--check-builtins s builtins what)
        (jetpacs-shell--check-features s features what)
        ;; 18.5 notification actions are invisible to the generic walker.
        (dolist (desc (jetpacs-shell--meta-descriptors s))
          (jetpacs-shell--check-builtins desc builtins what)
          (jetpacs-shell--check-features desc features what))))))

(defconst jetpacs-shell--aggregate-limits
  '((:max_rich_spans "rich_text" . :spans)
    (:max_table_cells "table_row" . :cells)
    (:max_chart_points "chart" . :series)
    (:max_canvas_ops "canvas" . :ops))
  "Welcome limit -> (NODE-TYPE . CHILD-MEMBER) for GATE 5's aggregate walk.
SPEC 4.5: these are counts across ONE SurfaceSpec, not per node.")

(defun jetpacs-shell--count-aggregates (spec)
  "Aggregate counts and the deepest node path in SPEC, as one plist.
Keys are the `jetpacs-shell--aggregate-limits' limit names plus
`:depth'.  One walk: GATE 5 runs on every push, and a traversal per
limit would cost more than the gate saves."
  (let ((counts (list :depth 0)))
    (cl-labels
        ((bump (key n)
           (setq counts (plist-put counts key (+ n (or (plist-get counts key)
                                                       0)))))
         (walk (node depth)
           (cond
            ((vectorp node) (mapc (lambda (v) (walk v depth)) node))
            ((and (consp node) (keywordp (car node)))
             (when (> depth (plist-get counts :depth))
               (setq counts (plist-put counts :depth depth)))
             (let ((type (plist-get node :t)))
               (pcase-dolist (`(,limit ,want . ,member)
                              jetpacs-shell--aggregate-limits)
                 (when (equal type want)
                   (bump limit
                         (if (equal type "chart")
                             ;; A chart's aggregate is POINTS, across series.
                             (apply #'+ 0
                                    (mapcar
                                     (lambda (se)
                                       (length (append (plist-get se :points)
                                                       nil)))
                                     (append (plist-get node member) nil)))
                           (length (append (plist-get node member) nil)))))))
             (let ((p node))
               (while p
                 (let ((k (pop p)) (v (pop p)))
                   (unless (memq k jetpacs--opaque-members)
                     (walk v (if (memq k '(:children :body :views))
                                 (1+ depth) depth)))))))
            ((consp node) (mapc (lambda (v) (walk v depth)) node))
            ((hash-table-p node)
             (maphash (lambda (_k v) (walk v (1+ depth))) node)))))
      (walk spec 1))
    counts))

(defun jetpacs-shell--gate-size (client spec stale-spec)
  "GATE 5: SPEC 4.5 SIZE — the sender MUST respect the reported limits.
`max_frame_bytes', the four aggregate counts, and the fixed 20-level
`max_node_depth'.  Nothing else in the sender measured any of these: the
renderer budgets its own spans and bytes, but a spec assembled by any
other builder — a chrome stack, a skin, a third-party Tier-1 — reached
the socket unmeasured.  Over-frame is worse than a 1201: SPEC 6.2 makes
it a `1400 frame-too-large' and a CLOSED connection."
  (let ((limits (ebp-client-limits client)))
    (dolist (s (delq nil (list spec stale-spec)))
      (when-let* ((frame (plist-get limits :max_frame_bytes)))
        (let ((bytes (string-bytes (jetpacs-node->canonical-json s))))
          (when (> bytes (- frame jetpacs-shell--frame-headroom))
            (error "jetpacs: spec is %d octets, over max_frame_bytes %d (SPEC 4.5)"
                   bytes frame))))
      (let ((counts (jetpacs-shell--count-aggregates s)))
        (when (> (plist-get counts :depth) jetpacs-shell--max-node-depth)
          (error "jetpacs: node depth %d exceeds max_node_depth %d (SPEC 4.5)"
                 (plist-get counts :depth) jetpacs-shell--max-node-depth))
        (pcase-dolist (`(,limit . ,_) jetpacs-shell--aggregate-limits)
          (when-let* ((cap (plist-get limits limit))
                      (n (plist-get counts limit)))
            (when (> n cap)
              (error "jetpacs: %d exceeds %s %d (SPEC 4.5 aggregate)"
                     n (substring (symbol-name limit) 1) cap))))))))

(defun jetpacs-shell--gate-capability (client surface)
  "GATE 3: a non-app namespace needs its granted surface capability."
  (let ((need (pcase (jetpacs-shell--surface-target surface)
                (:notification "surfaces.notification")
                (:widget "surfaces.widget")
                (:tile "surfaces.tile")
                (_ nil))))
    (when (and need (not (jetpacs-granted-p need client)))
      (error "jetpacs: %s push requires the ungranted %S capability"
             surface need))))

(defun jetpacs-shell--gate-amendments (client spec)
  "GATE 4: the ratified sender gates.
Amendment #85: a `wake' descriptor without this session's
`offline.wake' grant is 1201 content-invalid and voids the surface —
refuse before pushing.  SPEC 19/17.4: a synchronized `editor' (one
carrying `document') requires the `editor.sync' grant.  Amendment #84:
its document text must not exceed `max_editor_bytes'."
  (let* ((editor-granted (jetpacs-granted-p "editor.sync" client))
         (max-bytes (plist-get (ebp-client-limits client)
                               :max_editor_bytes))
         (check
          (lambda (p)
            ;; One authority for the 14.1 policy gate: the floor helper
            ;; every other descriptor emitter calls too.
            (jetpacs--gate-descriptor-policy p client)
            (when (and (equal (plist-get p :t) "editor")
                       (plist-get p :document))
              ;; The grant check must NOT hang off max-bytes: that limit is
              ;; REQUIRED only WHEN editor.sync is granted, so keying on it
              ;; made this branch dead in exactly the ungranted case.
              (unless editor-granted
                (error "jetpacs: synchronized editor %S requires the \
ungranted `editor.sync' capability (SPEC 19)" (plist-get p :id)))
              ;; Size the LIVE document, not `:value' — that is an optional
              ;; seed and is absent when re-pushing an already-open editor,
              ;; which is precisely when the text has grown.
              (let* ((doc (plist-get p :document))
                     (eid (plist-get p :id))
                     (text (or (and doc eid
                                    (ebp-client-editor-text client doc eid))
                               (plist-get p :value))))
                (when (and max-bytes (stringp text)
                           (> (string-bytes
                               (condition-case nil
                                   (json-serialize text)
                                 (error (make-string (1+ max-bytes) ?x))))
                              max-bytes))
                  (error "jetpacs: editor %S document exceeds \
max_editor_bytes (SPEC 19, amendment #84)" eid)))))))
    (jetpacs-shell--walk-plists spec check)
    ;; 18.5 notification action descriptors are opaque to the walker, and
    ;; they are the ONLY place 18.5 puts a descriptor — i.e. exactly where
    ;; the #85 wake gate matters most.
    (dolist (desc (jetpacs-shell--meta-descriptors spec))
      (jetpacs-shell--walk-plists desc check))))

;;;; The push

(defun jetpacs-shell--confirm-applied (surface revision status error)
  "Record REVISION as confirmed-applied for SURFACE when it really was.
Feeds `jetpacs-event-stale-p'; a refused push must NOT raise the bar."
  (when (and (null error) (equal status "applied") (integerp revision))
    (puthash surface
             (max revision (gethash surface jetpacs--applied-revisions -1))
             jetpacs--applied-revisions)))

(defun jetpacs-shell--push-callback (status error)
  "Default `surface.update' result callback.
`applied' and `stale' are both success (SPEC 13.2 idempotency); check
ERROR, not STATUS — a {} result leaves both nil."
  (when error
    ;; Code and kind only: an error's `data' may quote the offending
    ;; object path or value (SPEC 23.3, amendment #74).
    (message "jetpacs: surface.update failed: code %s (%s)"
             (plist-get error :code)
             (or (plist-get (plist-get error :data) :kind) "?")))
  status)

(cl-defun jetpacs-shell-push (&optional surface-or-owner
                              &key spec current-view stale-after-s
                              stale-spec reset-input-ids callback)
  "Push SURFACE-OR-OWNER's snapshot; returns the claimed revision or nil.
Zero-arg re-renders the current owner's surface (decision D1), else
`jetpacs-shell-surface-id' — the meaning `jetpacs-async--flush-push'
and `jetpacs-buffer-refresh-function' depend on.  SURFACE-OR-OWNER is a
surface id (with a colon) or a bare owner (`app:<owner>').

:SPEC overrides the registered builder for one push.  The four runtime
gates run in order (see the Commentary); a gate failure signals — the
SPEC 16.2/10.2 sender MUSTs are loud, never sanitized.  On any failure
a queued `jetpacs-shell-notify' snackbar is requeued for the next push."
  (let* ((surface (jetpacs-shell--resolve-surface surface-or-owner))
         (entry (alist-get surface jetpacs-shell--roots nil nil #'equal)))
    (jetpacs-shell--drop-pending surface)
    (cond
     ((and (null entry) (null spec)) nil)      ; nothing registered
     ((not (or jetpacs-shell--in-barrier (jetpacs-connected-p)))
      ;; Refused, but not always forgotten.  During SYNCING this is the
      ;; replay window: a replayed event's handler accepts and defers its
      ;; re-push per D2, the deferral fires before READY, and dropping it
      ;; here leaves the device showing the pre-event snapshot until the
      ;; user's NEXT interaction — Emacs state right, display stale.
      ;; Found by smoke-a8-coldstart on hardware.  Queue it for the READY
      ;; drain (`jetpacs-shell--on-ready') whenever a builder is
      ;; registered — the drain re-renders CURRENT state through it, so a
      ;; one-off :spec's exact payload is not retained and does not need
      ;; to be (the builder's fresh render is the D2 contract).  A pure
      ;; :spec push with NO registered root has nothing to re-render and
      ;; stays dropped, as do fully DISCONNECTED pushes: the barrier's
      ;; required-root push is the designed reconnect path.
      (when (and entry
                 (jetpacs-client)
                 (eq (ebp-client-state (jetpacs-client)) 'syncing))
        (cl-pushnew surface jetpacs-shell--repush-pending :test #'equal))
      nil)
     (t
      (let ((client (jetpacs-client-or-error))
            (snack (prog1 jetpacs-shell--snackbar
                     (setq jetpacs-shell--snackbar nil)))
            (revision nil))
        (unwind-protect
            (let* ((spec (or spec (jetpacs-shell--build surface entry)))
                   (stale-spec
                    (or stale-spec
                        (when-let* ((fn (plist-get entry :stale-builder)))
                          (funcall fn))))
                   (stale-after-s (or stale-after-s
                                      (plist-get entry :stale-after-s))))
              ;; GATE 2 first half: stale_spec discipline (SPEC 13.5).
              (when stale-spec
                (unless (eq (not (plist-member spec :views))
                            (not (plist-member stale-spec :views)))
                  (error "jetpacs: stale_spec must be the same variant \
as spec (SPEC 13.4/13.5)"))
                (setq stale-spec
                      (jetpacs-shell--validate-stripped
                       stale-spec
                       (jetpacs-shell--strip-stateful stale-spec))))
              ;; GATE 2 second half: `current_view' is valid ONLY for a
              ;; multi-view `app:*' spec (SPEC 13.4), and must name a view
              ;; that exists — a stale name is content-invalid.
              (unless (and (plist-member spec :views)
                           (eq (jetpacs-shell--surface-target surface) :app))
                (setq current-view nil))
              (when current-view
                (unless (gethash current-view (plist-get spec :views))
                  (error "jetpacs: current_view %S names no view in this \
spec (SPEC 13.4)" current-view)))
              ;; GATE 1, GATE 3, GATE 4.
              (jetpacs-shell--gate-spec client surface spec stale-spec)
              (jetpacs-shell--gate-capability client surface)
              (jetpacs-shell--gate-amendments client spec)
              (jetpacs-shell--gate-size client spec stale-spec)
              (when stale-spec
                (jetpacs-shell--gate-amendments client stale-spec))
              ;; Snackbar rides the scaffold slot when the root is one —
              ;; injected only after every gate passed, and drained only
              ;; after the send, so a refused push keeps the feedback.
              ;; (:snackbar is a string member; it adds no node types or
              ;; builtins, so injecting post-gate is sound.)
              (when (and snack (equal (plist-get spec :t) "scaffold"))
                (setq spec (append spec (list :snackbar snack))))
              ;; Send; the update result arrives async, the revision now.
              (jetpacs--claim "surface" surface)
              (setq revision
                    (ebp-client-surface-update
                     client surface spec
                     :stale-after-s stale-after-s
                     :stale-spec stale-spec
                     :current-view current-view
                     :reset-input-ids reset-input-ids
                     :callback
                     (lambda (status error)
                       (jetpacs-shell--confirm-applied
                        surface revision status error)
                       ;; B8: a W10 sender-ceiling refusal is transient
                       ;; and never reached the wire — a surface with a
                       ;; registered root retries via the debounced
                       ;; repush (the same machinery the READY drain
                       ;; uses); a rootless :spec push stays dropped.
                       (when (and (jetpacs-refused-p error)
                                  (alist-get surface jetpacs-shell--roots
                                             nil nil #'equal))
                         (jetpacs-shell--schedule-repush surface))
                       (funcall (or callback
                                    #'jetpacs-shell--push-callback)
                                status error))))
              ;; The push is on the wire: drain the slot, degrading to a
              ;; gated toast when no scaffold slot could carry it (an
              ;; ungranted Companion just loses the feedback — stale
              ;; feedback later would be worse).
              (when snack
                (unless (equal (plist-get spec :t) "scaffold")
                  (ignore-errors (jetpacs-toast snack)))
                (setq snack nil))
              (run-hooks 'jetpacs-shell-after-push-hook)
              revision)
          ;; A failed push showed nothing: the feedback must survive.
          (when snack
            (setq jetpacs-shell--snackbar
                  (or jetpacs-shell--snackbar snack)))))))))

(defun jetpacs-shell-refresh (&rest _)
  "Run `jetpacs-shell-refresh-hook', then push.  Hook-safe arity."
  (run-hooks 'jetpacs-shell-refresh-hook)
  (jetpacs-shell-push))

(defun jetpacs-shell-notify (text)
  "Queue TEXT as the next push's snackbar.  One slot; latest wins.
The Companion re-shows a snackbar only when its text changes."
  (setq jetpacs-shell--snackbar text))

;;;; Reconnect (SPEC 10.3 step 3, installed by `jetpacs-connect')

(defun jetpacs-shell--before-replay (_client)
  "Push every :required root before `queue.replay', while `syncing'.
The barrier flag bypasses the READY guard: SPEC 10.3 step 3 orders
required surface pushes ahead of replay."
  (let ((jetpacs-shell--in-barrier t))
    ;; Tombstones first: a surface removed while disconnected must be
    ;; retired before the session decides what is present (SPEC 13.3).
    (let ((pending jetpacs-shell--pending-removals))
      (setq jetpacs-shell--pending-removals nil)
      (dolist (surface pending)
        (condition-case err
            ;; The callback path catches async/local-1401 conclusions
            ;; the bare send silently lost; this condition-case still
            ;; catches synchronous SIGNALS.
            (jetpacs-shell--send-remove surface)
          (error
           (cl-pushnew surface jetpacs-shell--pending-removals :test #'equal)
           (message "jetpacs: deferred removal of %s failed: %s"
                    surface (jetpacs--error-label err))))))
    (pcase-dolist (`(,surface . ,entry) jetpacs-shell--roots)
      (when (plist-get entry :required)
        (condition-case err
            (jetpacs-shell-push surface)
          (error (message "jetpacs: reconnect push of %s failed: %s"
                          surface (jetpacs--error-label err))))))))

;;;; view.switched (SPEC 14.2 / 24.2)

(defvar jetpacs-shell-view-change-functions nil
  "Abnormal hook run with (SURFACE VIEW) after a local view switch.")

(defvar jetpacs-shell--current-view (make-hash-table :test #'equal)
  "Map of SURFACE -> the view the Companion last reported showing.")

(defun jetpacs-shell-current-view (surface)
  "The view SURFACE is currently showing, per the Companion's report."
  (gethash (jetpacs-shell--resolve-surface surface)
           jetpacs-shell--current-view))

;; SPEC 14.2: the `view.switch' builtin switches locally and, while READY,
;; reports `view.switched'.  "Emacs core conformance includes the generated
;; `view.switched' action and MUST allowlist its {view} arguments and
;; surface context" — without this registration ebp answers every tab tap
;; `rejected "action not allowlisted"' and the phone shows an error.
(jetpacs-defaction "view.switched"
  (lambda (args params)
    (let ((view (plist-get args :view))
          (surface (plist-get params :surface)))
      (if (not (and (stringp view) (stringp surface)))
          'rejected
        (puthash surface view jetpacs-shell--current-view)
        (run-hook-with-args 'jetpacs-shell-view-change-functions
                            surface view)
        'accepted))))

;;;; Seams

;; The async generation sweep rides every successful push.
(add-hook 'jetpacs-shell-after-push-hook #'jetpacs-async--after-push)

;; JC-1's buffer renderer refreshes through the shell once it loads.
(with-eval-after-load 'jetpacs-buffer
  (setq jetpacs-buffer-refresh-function #'jetpacs-shell-push))

(provide 'jetpacs-shell)
;;; jetpacs-shell.el ends here
