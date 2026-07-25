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

(defvar jetpacs-shell--repush-timer nil
  "The idle timer draining `jetpacs-shell--repush-pending'.")

(defvar jetpacs-shell--in-barrier nil
  "Non-nil during the SPEC 10.3 step-3 required-root push, where the
session is still `syncing' and the READY guard must not apply.")

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
  "Unregister SURFACE's root; tombstone it when connected (SPEC 13.3)."
  (let ((surface (jetpacs-shell--resolve-surface surface)))
    (setf (alist-get surface jetpacs-shell--roots nil 'remove #'equal) nil)
    (jetpacs--unclaim "surface" surface)
    (when (jetpacs-connected-p)
      (ebp-client-surface-remove (jetpacs-client) surface))))

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

;;;; Building (degrade in place: the live-coding contract)

(defun jetpacs-shell--build (surface plist)
  "Call SURFACE's :builder from PLIST; a crash degrades to an error view.
A broken builder costs its own screen, never the whole push."
  (condition-case err
      (funcall (plist-get plist :builder))
    (error
     (jetpacs-column
      (jetpacs-text (format "Error building %s" surface) :style "title")
      (jetpacs-text (error-message-string err) :style "body")))))

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
          (builtins (append (plist-get profile :builtins) nil)))
      (jetpacs-check-node-types spec types what)
      (jetpacs-shell--check-builtins spec builtins what)
      (when stale-spec
        (jetpacs-check-node-types stale-spec types what)
        (jetpacs-shell--check-builtins stale-spec builtins what)))))

(defun jetpacs-shell--gate-capability (client surface)
  "GATE 3: a non-app namespace needs its granted surface capability."
  (let ((need (pcase (jetpacs-shell--surface-target surface)
                (:notification "surfaces.notification")
                (:widget "surfaces.widget")
                (:tile "surfaces.tile")
                (_ nil))))
    (when (and need
               (not (seq-contains-p (ebp-client-granted client) need)))
      (error "jetpacs: %s push requires the ungranted %S capability"
             surface need))))

(defun jetpacs-shell--gate-amendments (client spec)
  "GATE 4: the ratified sender gates.
Amendment #85: a `wake' descriptor without this session's
`offline.wake' grant is 1201 content-invalid and voids the surface —
refuse before pushing.  Amendment #84: a synchronized editor whose
document text exceeds `max_editor_bytes' must not be presented."
  (let ((wake-granted (seq-contains-p (ebp-client-granted client)
                                      "offline.wake"))
        (max-bytes (plist-get (ebp-client-limits client)
                              :max_editor_bytes)))
    (jetpacs-shell--walk-plists
     spec
     (lambda (p)
       (when (and (not wake-granted)
                  (equal (plist-get p :when_offline) "wake"))
         (error "jetpacs: `wake' descriptor without the offline.wake \
grant (SPEC 14.1, amendment #85)"))
       (when (and max-bytes
                  (equal (plist-get p :t) "editor")
                  (plist-get p :document)
                  (stringp (plist-get p :value))
                  (> (string-bytes (json-serialize (plist-get p :value)))
                     max-bytes))
         (error "jetpacs: editor %S document exceeds max_editor_bytes \
(SPEC 19, amendment #84)"
                (plist-get p :id)))))))

;;;; The push

(defun jetpacs-shell--push-callback (status error)
  "Default `surface.update' result callback.
`applied' and `stale' are both success (SPEC 13.2 idempotency); check
ERROR, not STATUS — a {} result leaves both nil."
  (when error
    (message "jetpacs: surface.update failed: %S" error))
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
    (when (timerp jetpacs-shell--repush-timer)
      (cancel-timer jetpacs-shell--repush-timer)
      (setq jetpacs-shell--repush-timer nil
            jetpacs-shell--repush-pending nil))
    (cond
     ((and (null entry) (null spec)) nil)      ; nothing registered
     ((not (or jetpacs-shell--in-barrier (jetpacs-connected-p))) nil)
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
                (let ((stripped (jetpacs-shell--strip-stateful stale-spec)))
                  ;; A wholly-stateful stale root strips to nothing; say so
                  ;; rather than silently pushing without a stale view.
                  (unless stripped
                    (display-warning
                     'jetpacs
                     "stale_spec was entirely stateful (SPEC 13.5); dropped"
                     :warning))
                  (setq stale-spec stripped)))
              ;; GATE 2 second half: current_view only for multi-view.
              (unless (plist-member spec :views)
                (setq current-view nil))
              ;; GATE 1, GATE 3, GATE 4.
              (jetpacs-shell--gate-spec client surface spec stale-spec)
              (jetpacs-shell--gate-capability client surface)
              (jetpacs-shell--gate-amendments client spec)
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
                     :callback (or callback
                                   #'jetpacs-shell--push-callback)))
              ;; The push is on the wire: drain the slot, degrading to a
              ;; toast when no scaffold slot could carry it.
              (when snack
                (unless (equal (plist-get spec :t) "scaffold")
                  (ignore-errors (ebp-client-toast client snack)))
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
    (pcase-dolist (`(,surface . ,entry) jetpacs-shell--roots)
      (when (plist-get entry :required)
        (condition-case err
            (jetpacs-shell-push surface)
          (error (message "jetpacs: reconnect push of %s failed: %s"
                          surface (error-message-string err))))))))

;;;; Seams

;; The async generation sweep rides every successful push.
(add-hook 'jetpacs-shell-after-push-hook #'jetpacs-async--after-push)

;; JC-1's buffer renderer refreshes through the shell once it loads.
(with-eval-after-load 'jetpacs-buffer
  (setq jetpacs-buffer-refresh-function #'jetpacs-shell-push))

(provide 'jetpacs-shell)
;;; jetpacs-shell.el ends here
