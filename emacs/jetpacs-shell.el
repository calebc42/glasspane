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

(defvar jetpacs-shell--snackbars (make-hash-table :test #'equal)
  "SURFACE id -> queued snackbar text for its next push; latest wins.
Keyed by surface because D1 gives every owner its own: one global slot
let owner A's queued confirmation drain into owner B's push.")

(defvar jetpacs-shell--repush-pending nil
  "Surfaces awaiting the debounced registry repush.")

(defvar jetpacs-shell--refusal-counts (make-hash-table :test #'equal)
  "SURFACE -> consecutive W10-refused pushes; reset on any success.")

(defcustom jetpacs-shell-refusal-max-retries 8
  "Consecutive refusal-driven repushes per surface before giving up.
The ceiling clears as in-flight requests conclude, so a bounded retry
almost always lands; past the cap the surface waits for the next
natural push or the reconnect barrier instead of hammering a loaded
session."
  :type 'natnum :group 'jetpacs)

(defun jetpacs-shell--note-refusal (surface)
  "Record one refusal for SURFACE; schedule the backed-off repush.
First refusal repushes on the normal debounce; later ones double the
delay (capped at 30 s); past `jetpacs-shell-refusal-max-retries' stop —
pre-fix this loop was unbounded AND backoff-free."
  (let ((n (1+ (gethash surface jetpacs-shell--refusal-counts 0))))
    (puthash surface n jetpacs-shell--refusal-counts)
    (cond
     ((> n jetpacs-shell-refusal-max-retries)
      (message "jetpacs: %s refused %d times; waiting for a natural push"
               surface (1- n))
      nil)
     ((= n 1) (jetpacs-shell--schedule-repush surface))
     (t (run-at-time (min 30.0 (* 0.5 (expt 2.0 (1- n)))) nil
                     #'jetpacs-shell--schedule-repush surface)))))

(defvar jetpacs-shell--pending-removals nil
  "Surfaces whose tombstone could not be sent while disconnected.
Flushed at the next Section 10.3 barrier; without this a removal made
offline is lost and the surface stays present forever (SPEC 4.5
`max_surfaces').")

(defvar jetpacs-shell--tombstoned (make-hash-table :test #'equal)
  "Surfaces whose SPEC 13.3 tombstone this session already issued.
`jetpacs-teardown-owner''s send-guard reads it: the claimed REVISION
survives in the client after a removal (13.3 keeps tombstones), so
\"root or revision\" re-fired the tombstone on every later teardown of
the same owner — measured, three calls was three sends.  A
re-registration (`jetpacs-shell-define-root') clears the mark.")

(defvar jetpacs-shell--repush-timer nil
  "The idle timer draining `jetpacs-shell--repush-pending'.")

(defvar jetpacs-shell--in-barrier nil
  "Non-nil during the SPEC 10.3 step-3 required-root push, where the
session is still `syncing' and the READY guard must not apply.")

(defconst jetpacs-shell--frame-headroom 2048
  "Octets GATE 5 reserves from `max_frame_bytes' for the envelope.")

(defconst jetpacs-shell--max-node-depth 20
  "SPEC 4.5 fixed `max_node_depth' (contract limits.fixed).")

(defconst jetpacs-shell--max-nodes 10000
  "SPEC 4.5 fixed `max_nodes_per_snapshot' (contract limits.fixed).")

(defconst jetpacs-shell--max-children 10000
  "SPEC 4.5 fixed `max_children_per_node' (contract limits.fixed).")

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

;; Defined with the view machinery at the end of the file; declared here
;; because the registry, the push path and teardown all sweep them.
(defvar jetpacs-shell--current-view)
(defvar jetpacs-shell--unasserted-view)

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
    (remhash surface jetpacs-shell--tombstoned)
    (setf (alist-get surface jetpacs-shell--roots nil nil #'equal)
          (list :builder builder :owner jetpacs-current-owner
                :required required :stale-after-s stale-after-s
                :stale-builder stale-builder))
    (jetpacs-shell--schedule-repush surface)
    surface))

(defun jetpacs-shell-roots ()
  "Live root registrations as an alist of (SURFACE . OWNER), a copy.
OWNER is the id recorded at registration (nil for an ownerless root).
The launcher's read surface: everything with a registered builder is an
app a user could switch to, and nothing else is."
  (mapcar (lambda (entry)
            (cons (car entry) (plist-get (cdr entry) :owner)))
          jetpacs-shell--roots))

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
    (remhash surface jetpacs-shell--current-view)
    (remhash surface jetpacs-shell--unasserted-view)
    (puthash surface t jetpacs-shell--tombstoned)
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
       ;; Discriminate: a PERMANENT protocol answer (-32601 unknown
       ;; method, 1201 content-invalid) will only re-fail — requeueing
       ;; re-sends it at every 10.3 barrier forever.  Everything else
       ;; (the local W10 refusal, timeouts, transport loss) is transient
       ;; and the barrier retry is exactly right.
       (if (memql (plist-get error :code) '(-32601 1201))
           (message "jetpacs: surface.remove of %s permanently refused \
(code %s); dropping the tombstone" surface (plist-get error :code))
         (cl-pushnew surface jetpacs-shell--pending-removals :test #'equal)
         (message "jetpacs: surface.remove of %s failed (code %s, %s); \
queued for the next barrier"
                  surface (plist-get error :code)
                  (or (plist-get (plist-get error :data) :kind) "?")))))))

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
  ;; The surface list is computed ONCE, before the sweep, and published
  ;; to the hooks in `jetpacs-teardown-surfaces' — the sweep itself
  ;; unclaims as it goes, so any later recomputation sees only the D1
  ;; primary.
  (let ((jetpacs-teardown-surfaces (jetpacs-shell--owner-surfaces owner))
        (client (jetpacs-client)))
    (dolist (surface jetpacs-teardown-surfaces)
      (jetpacs-on-state-change-clear "" surface)
      (if (and (not (gethash surface jetpacs-shell--tombstoned))
               (or (alist-get surface jetpacs-shell--roots nil nil #'equal)
                   (and client
                        (gethash surface (ebp-client-revisions client)))))
          (jetpacs-shell-remove-root surface)
        (jetpacs--unclaim "surface" surface))
      (remhash surface jetpacs--applied-revisions)
      (remhash surface jetpacs-shell--current-view)
      (remhash surface jetpacs-shell--unasserted-view))
    ;; `run-hook-wrapped', not `dolist': a buffer-local `add-hook' puts
    ;; `t' in the value, and `(funcall t owner)' would be swallowed by
    ;; the isolation below — silently dropping every GLOBAL subscriber.
    (run-hook-wrapped
     'jetpacs-teardown-functions
     (lambda (fn)
       (condition-case err
           (funcall fn owner)
         (error (message "jetpacs: teardown hook failed: %s"
                         (jetpacs--error-label err))))
       nil)))
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
                 (dolist (s surfaces)
                   ;; Isolated per surface, matching `--on-ready': one
                   ;; owner's gate failure must not drop every OTHER
                   ;; owner's queued re-render on the floor.
                   (condition-case err
                       (jetpacs-shell-push s)
                     (error (message "jetpacs: repush of %s failed: %s"
                                     s (jetpacs--error-label err))))))))))))

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
                      jetpacs-current-owner)))
            ;; ONE claim table per document (SPEC 16.1 scopes id
            ;; uniqueness to the COMPLETE surface document): every minter
            ;; below this build — chrome screens, sections, comint —
            ;; joins it, so two renders of one buffer in one document
            ;; route around each other instead of shipping a duplicate.
            (jetpacs-node-id-claims (make-hash-table :test #'equal)))
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
  "Aggregate counts, node totals, and the deepest node path in SPEC.
One plist: the `jetpacs-shell--aggregate-limits' keys plus `:depth',
`:nodes' and `:max-children'.  One walk — GATE 5 runs on every push.
Depth matches the Companion's validator: every TYPED node reached from
ANY non-opaque member is one level deeper than the node that carries it
— `:children' has no special status (a scaffold's `top_bar', a card's
content, a box in a box all nest), and non-node plists (descriptors,
spans) add no depth."
  (let ((counts (list :depth 0 :nodes 0 :max-children 0)))
    (cl-labels
        ((bump (key n)
           (setq counts (plist-put counts key
                                   (+ n (or (plist-get counts key) 0)))))
         (walk (value depth)
           (cond
            ((vectorp value)
             (mapc (lambda (v) (walk v depth)) value))
            ((hash-table-p value)
             (maphash (lambda (_k v) (walk v depth)) value))
            ((and (consp value) (keywordp (car value)))
             (let* ((type (plist-get value :t))
                    (typed (stringp type))
                    (d (if typed (1+ depth) depth)))
               (when typed
                 (bump :nodes 1)
                 (when (> d (plist-get counts :depth))
                   (setq counts (plist-put counts :depth d)))
                 (let ((kids (plist-get value :children)))
                   (when (and (vectorp kids)
                              (> (length kids)
                                 (plist-get counts :max-children)))
                     (setq counts (plist-put counts :max-children
                                             (length kids)))))
                 (pcase-dolist (`(,limit ,want . ,member)
                                jetpacs-shell--aggregate-limits)
                   (when (equal type want)
                     (bump limit
                           (if (equal type "chart")
                               ;; A chart's aggregate is POINTS, across
                               ;; series.
                               (apply #'+ 0
                                      (mapcar
                                       (lambda (se)
                                         (length (append
                                                  (plist-get se :points)
                                                  nil)))
                                       (append (plist-get value member)
                                               nil)))
                             (let ((v (plist-get value member)))
                               (if (vectorp v) (length v)
                                 (length (append v nil)))))))))
               (let ((p value))
                 (while p
                   (let ((k (pop p)) (v (pop p)))
                     (unless (memq k jetpacs--opaque-members)
                       (walk v d)))))))
            ((consp value)
             (walk (car value) depth)
             (walk (cdr value) depth)))))
      (walk spec 0))
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
        ;; Children BEFORE nodes: the caps are equal, so any children
        ;; breach is also a nodes breach — the specific diagnosis wins.
        (when (> (plist-get counts :max-children) jetpacs-shell--max-children)
          (error "jetpacs: %d children exceed max_children_per_node %d (SPEC 4.5)"
                 (plist-get counts :max-children)
                 jetpacs-shell--max-children))
        (when (> (plist-get counts :nodes) jetpacs-shell--max-nodes)
          (error "jetpacs: %d nodes exceed max_nodes_per_snapshot %d (SPEC 4.5)"
                 (plist-get counts :nodes) jetpacs-shell--max-nodes))
        (pcase-dolist (`(,limit . ,_) jetpacs-shell--aggregate-limits)
          (when-let* ((cap (plist-get limits limit))
                      (n (plist-get counts limit)))
            (when (> n cap)
              (error "jetpacs: %d exceeds %s %d (SPEC 4.5 aggregate)"
                     n (substring (symbol-name limit) 1) cap))))))))

(defun jetpacs-shell--gate-ids (spec stale-spec)
  "GATE 1d: SPEC 16.1 — no duplicate node id within one document.
SPEC and STALE-SPEC are checked SEPARATELY: the Companion validates
each with its own id set.  The claim table makes MINTED ids unique by
construction; this catches the literal authored duplicate (two screens
both hard-coding \"search\") that nothing else can, in every builder —
chrome degrades its screens first, so for a chrome document this is the
backstop, and for a plain root it is the only floor.  A duplicate is a
1201 for the ENTIRE update, and 13.2 then retains the old snapshot: the
sender MUST is loud."
  (dolist (s (delq nil (list spec stale-spec)))
    (let ((ids (jetpacs--collect-node-ids s nil))
          (seen (make-hash-table :test #'equal)))
      (dolist (id ids)
        (when (gethash id seen)
          (signal 'jetpacs-duplicate-node-id (list id)))
        (puthash id t seen)))))

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

:RESET-INPUT-IDS must name ids as EMITTED — resolve an authored base
through `jetpacs-claimed-node-id' when a document build may have
suffixed it, or the reset names a ghost and the push 1201s.

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
        ;; SPEC 10.3 step 4: this push never reached the wire either, and
        ;; the READY drain re-pushes with NO view — so a REPLAYED
        ;; handler's deferred navigation is owed for exactly the reason a
        ;; B8 refusal is.  Recorded UNVALIDATED on purpose: the spec is
        ;; not built here, and `jetpacs-shell--claim-view' re-checks the
        ;; name against the drain's own `views' and drops it if gone.
        (when (and current-view
                   (eq (jetpacs-shell--surface-target surface) :app))
          (puthash surface current-view jetpacs-shell--unasserted-view))
        (cl-pushnew surface jetpacs-shell--repush-pending :test #'equal))
      nil)
     (t
      (let ((client (jetpacs-client-or-error))
            (snack (prog1 (gethash surface jetpacs-shell--snackbars)
                     (remhash surface jetpacs-shell--snackbars)))
            ;; Whether the injection above found a scaffold slot; the drain
            ;; cannot re-derive it, since a multi_view injection rewrites a
            ;; VIEW rather than the root.
            (snack-in-scaffold nil)
            (refused nil)
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
              (jetpacs-shell--gate-ids spec stale-spec)
              (when stale-spec
                (jetpacs-shell--gate-amendments client stale-spec))
              ;; Snackbar rides the scaffold slot when the root is one —
              ;; injected only after every gate passed, and drained only
              ;; after the send, so a refused push keeps the feedback.
              ;; (:snackbar is a string member; it adds no node types or
              ;; builtins, so injecting post-gate is sound.)
              (when snack
                (if-let* ((injected (jetpacs-shell--inject-snackbar
                                     spec current-view snack)))
                    (setq spec injected snack-in-scaffold t)
                  (setq snack-in-scaffold nil)))
              ;; Re-assert a navigation the W10 ceiling refused, and
              ;; record the view this snapshot will leave the surface on —
              ;; BEFORE the send, because a refusal concludes its callback
              ;; INSIDE it (with `revision' still nil), and the
              ;; reconciliation below compares against this belief.
              (setq current-view
                    (jetpacs-shell--claim-view surface spec current-view))
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
                       (jetpacs-shell--view-result
                        surface current-view status error)
                       ;; B8: a W10 sender-ceiling refusal is transient
                       ;; and never reached the wire — a surface with a
                       ;; registered root retries via the debounced
                       ;; repush, now counted and BACKED OFF per surface
                       ;; (pre-fix: unbounded and backoff-free); a
                       ;; rootless :spec push stays dropped.  Any other
                       ;; conclusion resets the count.
                       (if (jetpacs-refused-p error)
                           (progn
                             (setq refused t)
                             (when (alist-get surface jetpacs-shell--roots
                                              nil nil #'equal)
                               (jetpacs-shell--note-refusal surface)))
                         (remhash surface jetpacs-shell--refusal-counts))
                       (funcall (or callback
                                    #'jetpacs-shell--push-callback)
                                status error))))
              ;; A W10 refusal concluded SYNCHRONOUSLY inside the send:
              ;; the frame never left, so the injected snackbar shipped
              ;; nowhere — requeue the user's feedback for the B8 retry
              ;; and SKIP the after-push hook (its contract is "after a
              ;; successful send", and the async generation sweep riding
              ;; it would retire loaders whose render never displayed).
              (if refused
                  (when snack
                    (puthash surface snack jetpacs-shell--snackbars)
                    (setq snack nil))
                ;; The push is on the wire: drain the slot, degrading to
                ;; a gated toast when no scaffold slot could carry it (an
                ;; ungranted Companion just loses the feedback — stale
                ;; feedback later would be worse).
                (when snack
                  (unless snack-in-scaffold
                    (ignore-errors (jetpacs-toast snack)))
                  (setq snack nil))
                (jetpacs-shell--run-isolated 'jetpacs-shell-after-push-hook))
              revision)
          ;; A failed push showed nothing: the feedback must survive.
          (when snack
            (unless (gethash surface jetpacs-shell--snackbars)
              (puthash surface snack jetpacs-shell--snackbars)))))))))

(defun jetpacs-shell--inject-snackbar (spec view snack)
  "SPEC with SNACK in a scaffold `snackbar' slot, or nil if there is none.

A §13.4 `app:*' spec is USUALLY a multi_view, not a scaffold: every
`jetpacs-chrome' screen is a `jetpacs-scaffold', and the stack wraps them
as VIEWS.  So the slot lives one level down, on the view being shown —
testing only the root\='s `:t\=' found no scaffold on any chrome app and
silently degraded every snackbar in the product to a toast.

VIEW is the view this push will land on (nil = the spec\='s own
`initial_view\=').  Returns nil when neither shape offers a scaffold, and
the caller degrades to a toast as before."
  (cond
   ((equal (plist-get spec :t) "scaffold")
    (append spec (list :snackbar snack)))
   ((plist-get spec :views)
    (let* ((views (plist-get spec :views))
           (vid (or view (plist-get spec :initial_view)))
           (root (and vid (gethash vid views))))
      (when (equal (plist-get root :t) "scaffold")
        ;; Copy-on-write: the caller\='s spec is not ours to mutate, and a
        ;; refused push must leave it exactly as it was.
        (let ((copy (copy-hash-table views)))
          (puthash vid (append root (list :snackbar snack)) copy)
          (plist-put (copy-sequence spec) :views copy)))))))

(defun jetpacs-shell--run-isolated (hook &rest args)
  "Run HOOK's functions with ARGS, each isolated; log failures by SYMBOL.
Isolation is not optional on any hook reachable from inside the jsonrpc
dispatch extent: the effect is already committed when the hook runs —
for the push hooks the frame is ON THE WIRE — and an escaping signal
answers `rejected', which SPEC 14.4 makes PERMANENT.  `run-hook-wrapped'
handles the buffer-local `t' marker a bare dolist would funcall."
  (apply #'run-hook-wrapped hook
         (lambda (fn &rest a)
           (condition-case err (apply fn a)
             (error (message "jetpacs: %s hook failed: %s"
                             hook (jetpacs--error-label err))))
           nil)
         args))

(defun jetpacs-shell-refresh (&rest _)
  "Run `jetpacs-shell-refresh-hook', then push.  Hook-safe arity."
  (jetpacs-shell--run-isolated 'jetpacs-shell-refresh-hook)
  (jetpacs-shell-push))

(defun jetpacs-shell-notify (text &optional surface-or-owner)
  "Show TEXT as a snackbar — the SPEC 18.2.1 raise when granted.
On a session with presentation.snackbar granted this raises
IMMEDIATELY in whatever scaffold is on screen: no re-push, no
injection, and multi_view needs no special casing because nothing is
spliced into a tree.  (The injection path below is the machinery whose
view-targeting bug once degraded every chrome snackbar to a toast —
the raise retires that whole class where the grant exists.)

Without the grant it queues TEXT as SURFACE-OR-OWNER's next-push
snackbar, latest wins.  SURFACE-OR-OWNER defaults through
`jetpacs-shell--resolve-surface' — with the dispatch binding the
acting owner (E2a), a handler's feedback lands on that owner's surface
without naming it.  The Companion re-shows a snackbar only when its
text changes."
  (if (and (jetpacs-connected-p)
           (jetpacs-granted-p "presentation.snackbar"))
      (condition-case err
          (ebp-client-snackbar-show (jetpacs-client) text)
        (error (message "jetpacs-shell: snackbar raise failed: %s"
                        (jetpacs--error-label err))))
    (puthash (jetpacs-shell--resolve-surface surface-or-owner)
             text jetpacs-shell--snackbars)))

;;;; Reconnect (SPEC 10.3 step 3, installed by `jetpacs-connect')

(defun jetpacs-shell--before-replay (_client)
  "Push every :required root before `queue.replay', while `syncing'.
The barrier flag bypasses the READY guard: SPEC 10.3 step 3 orders
required surface pushes ahead of replay."
  (let ((jetpacs-shell--in-barrier t))
    ;; A navigation owed from the PREVIOUS session is unknowable-stale:
    ;; Companion-local `view.switch' while not READY is never reported,
    ;; so offline drift is invisible here, and the standing decision
    ;; (chrome Commentary) is that the drift is benign — never force
    ;; `current_view' on reconnect.  Runs at 10.3 step 3, BEFORE replay
    ;; delivers events, so a SYNCING-window debt recorded during step 4
    ;; is never wiped by this.
    (clrhash jetpacs-shell--unasserted-view)
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
  "Map of SURFACE -> the view Emacs believes the Companion is showing.
Written by `jetpacs-shell--record-view' from two authorities: the push
path, which knows what SPEC 13.4 makes the Companion select, and the
Companion's own `view.switched'.  Before this was written by the push
path too, the public accessor LIED after every Emacs-driven navigation
— `view.switched' is generated only by the `view.switch' builtin.")

(defvar jetpacs-shell--unasserted-view (make-hash-table :test #'equal)
  "Map of SURFACE -> a `current_view' a refused push never delivered.
A B8 refusal concludes locally and never touches the wire, and a
SYNCING-window push is dropped before the wire too — in both the
navigation is still OWED: the next push for that surface re-asserts it
once.  Safety comes from consumption order, not from an entry always
matching the belief: `jetpacs-shell--claim-view' adopts the owed entry
BEFORE `--record-view' runs for that push, so the debt is consumed by
the surface's next push before any newer belief can invalidate it, and
`--record-view' drops the entry on any CHANGE of belief (a later push,
a Companion `view.switched') — a SYNCING-owed entry has no belief
behind it at all, which is fine for the same reason."
  )

(defun jetpacs-shell-current-view (surface)
  "The view SURFACE is showing: the Companion's last report, else the
view SPEC 13.4 makes its last accepted snapshot select.  Optimistic — a
push refused before it reached the wire is believed until its retry
lands (`jetpacs-shell--unasserted-view' is that debt)."
  (gethash (jetpacs-shell--resolve-surface surface)
           jetpacs-shell--current-view))

(defun jetpacs-shell--record-view (surface view)
  "Record VIEW as SURFACE's believed current view; nil means none.
The single authority.  A CHANGE of value invalidates any unasserted
navigation, which is what stops a refused view yanking the user back
after they have moved on."
  (if view
      (puthash surface view jetpacs-shell--current-view)
    (remhash surface jetpacs-shell--current-view))
  (unless (equal view (gethash surface jetpacs-shell--unasserted-view))
    (remhash surface jetpacs-shell--unasserted-view)))

(defun jetpacs-shell--view-after-push (surface spec current-view)
  "The view SPEC leaves SURFACE showing once accepted (SPEC 13.4), or nil.
Deterministic at send time: 13.4 gives the Companion exactly three
reasons to change views and all three are decided here.  A snapshot
with no `views' leaves no current view at all — the Companion clears
what it retained."
  (let ((views (plist-get spec :views)))
    (cond
     ((not (hash-table-p views)) nil)
     (current-view current-view)
     (t (let ((held (gethash surface jetpacs-shell--current-view)))
          (if (and held (gethash held views))
              held
            (plist-get spec :initial_view)))))))

(defun jetpacs-shell--claim-view (surface spec current-view)
  "Adopt SURFACE's owed navigation into CURRENT-VIEW; record the result.
Returns the `current_view' to send.  Never signals: an owed view this
SPEC no longer contains is void intent, not an error — only a
CALLER-supplied name is a loud 13.4 violation."
  (let ((owed (gethash surface jetpacs-shell--unasserted-view))
        (views (plist-get spec :views)))
    (unless current-view
      (if (and owed (hash-table-p views) (gethash owed views))
          (setq current-view owed)
        (remhash surface jetpacs-shell--unasserted-view))))
  (jetpacs-shell--record-view
   surface (jetpacs-shell--view-after-push surface spec current-view))
  current-view)

(defun jetpacs-shell--view-result (surface view status error)
  "Reconcile SURFACE's owed-navigation slot with one push result.
VIEW is the `current_view' this push carried, nil for none.  Only a B8
refusal leaves the navigation owed — it provably never reached the
wire.  Everything else settles the debt: an `applied' is confirmation,
and a 1201/timeout would only re-fail, so keeping the debt would make
every later BACKGROUND refresh navigation-forcing (SPEC 13.4's
SHOULD-omit)."
  (when view
    (if (jetpacs-refused-p error)
        (when (equal view (gethash surface jetpacs-shell--current-view))
          (puthash surface view jetpacs-shell--unasserted-view))
      (when (equal view (gethash surface jetpacs-shell--unasserted-view))
        (remhash surface jetpacs-shell--unasserted-view))))
  status)

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
        (jetpacs-shell--record-view surface view)
        (jetpacs-shell--run-isolated 'jetpacs-shell-view-change-functions
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
