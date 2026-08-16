;;; glasspane-clock.el --- org-clock chronometer notification -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The legacy clock owner retained only for the GR-5 rollback window.
;; Native clock state, persistence, and chronometer delivery now live in
;; `jetpacs-org-clock'; this downstream copy stays inert unless
;; `glasspane-clock-enabled'.  Glasspane's opinionated clock-in placement
;; remains in its detail and reader screens, independent of this adapter.
;;
;; Retired against v1 (docs/PLAN-glasspane-app.md, retirement list +
;; G2): the whole `widget:custom1' home-screen clock widget block
;; (v1:60-92 — `jetpacs-widget-item' rows pushed off
;; `jetpacs-shell-after-push-hook') dies with FOUNDATION-GAPS #1: no
;; widget node vocabulary or Companion renderer exists; the
;; handler-side `jetpacs-dismiss-dialog' in clock.out (v1:43) — this
;; module opens no dialog of its own, so it holds no `dialog.show'
;; request id to `ebp-client-abandon' (S3), and a foundation sheet that
;; dispatches these verbs retires itself; and clock.switch's
;; `org-clock-goto' placeholder (v1:48) — a desktop point movement the
;; phone cannot see, so the verb answers `rejected' until a real task
;; picker exists.

;;; Code:

(require 'org-clock)
(require 'org-crypt)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-org-clock)

(defvar glasspane-clock-enabled nil
  "Non-nil to register the legacy clock engine during rollback only.
Native Org clock integration is the default owner after GR-5.  This flag and
file remain through the soak window so the cutover can be reversed without a
code rollback.")

(defconst glasspane-clock-surface "notification:org-clock"
  "The chronometer's surface id (SPEC 13.1; the v1 name, kept).")

(defconst glasspane-clock--ttl-s 3600
  "Offline ttl for the notification's clock actions (SPEC 14.1).
A non-drop policy requires one; an hour bounds a late delivery — the
running entry keeps accumulating until the occurrence lands, so an
older clock-out records a duration the user never meant.")

(defvar glasspane-clock--live nil
  "Non-nil while this Emacs has the notification root registered.
Gates re-registration so `jetpacs--claim' never sees a same-owner
re-claim from whatever file buffer a clock-in hook happens to run in,
and keeps retire from tombstoning a surface this session never
asserted (the grant-degraded case).")

;;;; The SurfaceSpec

(defun glasspane-clock--remote (name)
  "The notification's ActionDescriptor for verb NAME.
`wake' — the point of the notification is reaching a dead Emacs — but
only when the session holds `offline.wake': amendment #85 voids the
WHOLE surface at the push gate for an ungranted wake descriptor, so
the ungranted session degrades to `queue' rather than losing the
chronometer."
  (jetpacs-action name
                  :when-offline (if (jetpacs-granted-p "offline.wake")
                                    "wake" "queue")
                  :ttl-s glasspane-clock--ttl-s))

(defun glasspane-clock-notification-spec ()
  "The chronometer SurfaceSpec for the running clock.
SPEC 18.5: the buttons ride meta `:actions' — the notification node
set has no button — and the elapsed timer is `:chronometer' counting
up from the clock-in instant."
  (if (not (and (org-clock-is-active) org-clock-current-task))
      ;; The registry race arm: retire runs on `org-clock-out-hook',
      ;; but a debounced repush may still build once after the clock
      ;; died — and a crash here would degrade to the shell's error
      ;; view on the device.  A zero state is honest and quiet.
      (jetpacs-notification-surface
       (jetpacs-text "No running clock" :style "body")
       :meta (list :channel "clocking"))
    (jetpacs-notification-surface
     (jetpacs-text (format "Clocked in: %s" org-clock-current-task)
                   :style "title")
     :meta (list :channel "clocking"
                 :ongoing t
                 :category "stopwatch"
                 :chronometer
                 (list :base_ms (truncate
                                 (* 1000 (float-time org-clock-start-time))))
                 ;; Most important first: the platform may show fewer
                 ;; actions (SPEC 18.5).
                 :actions
                 (vector
                  (list :label "Clock out"
                        :on_tap (glasspane-clock--remote "org.clock.out"))
                  (list :label "Switch task"
                        :on_tap (glasspane-clock--remote
                                 "org.clock.switch")))))))

;;;; Assert / retire

(defun glasspane-clock-soon (fn)
  "Run FN now, or after the dispatch extent when inside one.
The D2 seam: a clock hook fired by `org-clock-out' INSIDE a handler
must not send from the dispatch extent; the same hook fired by a
desktop M-x needs no deferral."
  (if (jetpacs-in-action-p)
      (jetpacs-flow-continue fn)
    (funcall fn)))

(defun glasspane-clock--push ()
  "Re-render the live chronometer.
A SYNCING push queues itself for the READY drain; a gate failure costs
this surface only."
  (when glasspane-clock--live
    (condition-case err
        (jetpacs-shell-push glasspane-clock-surface)
      (error (message "glasspane-clock: push failed: %s"
                      (jetpacs-error-label err))))))

(defun glasspane-clock--assert ()
  "Mirror the running clock to the device, when the session may.
Ungranted `surfaces.notification' degrades the whole surface silently
— the push gate would SIGNAL (jetpacs-shell.el:720-726).  Disconnected
sessions also land in the guard (`jetpacs-granted-p' is nil with no
client, fail closed); `glasspane-clock--on-ready' re-asserts them."
  (when (and (org-clock-is-active)
             (jetpacs-granted-p "surfaces.notification"))
    (unless glasspane-clock--live
      (setq glasspane-clock--live t)
      ;; The owner claim puts the root under `jetpacs-teardown-owner''s
      ;; sweep.  It is NOT what admits the org.clock.* taps — those
      ;; verbs are global (see install-hooks): a durable tap replays
      ;; before this claim can exist.
      (with-jetpacs-owner "glasspane"
        (jetpacs-shell-define-root glasspane-clock-surface
                                   #'glasspane-clock-notification-spec)))
    (glasspane-clock-soon #'glasspane-clock--push)))

(defun glasspane-clock--retire ()
  "Take the chronometer down; a disconnected removal is REMEMBERED.
Never grant-gated: the grant may have been revoked mid-session and the
tombstone must still go out — `jetpacs-shell-remove-root' queues it
for the next barrier when offline."
  (when glasspane-clock--live
    (setq glasspane-clock--live nil)
    (glasspane-clock-soon
     (lambda () (jetpacs-shell-remove-root glasspane-clock-surface)))))

(defun glasspane-clock--on-ready (_client)
  "Settle BOTH directions of the phone's cache at READY (arity (CLIENT)).
That cache survives an Emacs restart; only Emacs knows whether the
clock still runs — so a running clock re-asserts, and a stopped one
retires the ongoing chronometer that would otherwise tick in the shade
forever.  The removal is deliberately NOT grant-gated (see
`glasspane-clock--retire': the tombstone goes out even with the grant
revoked) and NOT routed through `glasspane-clock-soon' — READY is not
a dispatch extent.  It clears `glasspane-clock--live' with the removal
for the same reason `glasspane-clock--retire' does: the flag names a
REGISTERED root, and a clock cancelled through `org-clock-cancel-hook'
\(which this module does not hook) leaves it set over a root this arm
drops — a later `glasspane-clock--assert' would then skip
`jetpacs-shell-define-root', the only thing that clears the tombstone,
and push into nothing for the rest of the session.  Runs in the late
depth-90 READY phase, after durable replay has settled."
  (if (org-clock-is-active)
      (glasspane-clock--assert)
    (setq glasspane-clock--live nil)
    (jetpacs-shell-remove-root glasspane-clock-surface)))

;;;; SPEC 14 handlers

(defun glasspane-clock--on-out (_args _params)
  "Stop the running clock; the durable effect is the clock state itself.
No running clock is `stale' — the notification the tap came from
outlived reality.  The save is deferred through the ebp-org funnel
\(the `ebp-org-with-mutation' convention: a deferred save still
answers `accepted'); the notification retires via `org-clock-out-hook'
outside this extent."
  (if (not (org-clock-is-active))
      'stale
    (let ((buf (and (markerp org-clock-marker)
                    (marker-buffer org-clock-marker))))
      (org-clock-out)
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (add-hook 'before-save-hook #'org-encrypt-entries nil t)
          (ebp-org-defer-save)))
      'accepted)))

(defun glasspane-clock--on-switch (_args _params)
  "Definitively refuse until a real task picker exists (plan G2).
v1 jumped desktop point (`org-clock-goto') — an effect the phone
cannot observe, which is worse than an honest refusal."
  'rejected)

(defun glasspane-clock--on-in-last (_args _params)
  "Resume the last clocked task.
An empty clock history signals (`user-error') and any resolve-idle
prompt dies under the no-prompt regime — both answer `rejected'.  The
notification asserts via `org-clock-in-hook' outside this extent."
  (condition-case err
      (progn
        (org-clock-in-last)
        (let ((buf (and (markerp org-clock-marker)
                        (marker-buffer org-clock-marker))))
          (when (buffer-live-p buf)
            (with-current-buffer buf
              (add-hook 'before-save-hook #'org-encrypt-entries nil t)
              (ebp-org-defer-save))))
        'accepted)
    (error
     ;; Label only: the datum may quote heading text (SPEC 23.3).
     (message "glasspane-clock: clock-in-last failed: %s"
              (jetpacs-error-label err))
     'rejected)))

;;;; Enable / disable (the glasspane-org hook-hygiene pattern)

(defun glasspane-clock--on-teardown (owner)
  "Detach with the app's OWNER; a foreign teardown is not ours."
  (when (equal owner "glasspane")
    ;; The owner sweep has already tombstoned the claimed surface;
    ;; mirror that here so remove-hooks' retire does not re-send it.
    (setq glasspane-clock--live nil)
    (glasspane-clock-remove-hooks)))

(defun glasspane-clock--undef-if-handler (name handler)
  "Undefine NAME only when HANDLER is still the legacy implementation."
  (when (eq (gethash name jetpacs-action-handlers) handler)
    (jetpacs-undefaction name)))

(defun glasspane-clock-remove-hooks ()
  "Detach everything `glasspane-clock-install-hooks' attached.
Retires a live chronometer first: disabling the app must not leave a
dead timer ticking in the phone's shade."
  (glasspane-clock--retire)
  ;; Idempotent against `jetpacs-teardown-owner', which sweeps the
  ;; owner's actions before the teardown hook lands here; the
  ;; unregister/unload path has no such sweep and needs these.
  (glasspane-clock--undef-if-handler
   "org.clock.out" #'glasspane-clock--on-out)
  (glasspane-clock--undef-if-handler
   "org.clock.switch" #'glasspane-clock--on-switch)
  (glasspane-clock--undef-if-handler
   "org.clock.in-last" #'glasspane-clock--on-in-last)
  (remove-hook 'org-clock-in-hook #'glasspane-clock--assert)
  (remove-hook 'org-clock-out-hook #'glasspane-clock--retire)
  (remove-hook 'jetpacs-ready-functions #'glasspane-clock--on-ready)
  (remove-hook 'jetpacs-teardown-functions #'glasspane-clock--on-teardown))

(defun glasspane-clock-install-hooks ()
  "Attach the clock-mirroring hooks and verbs, with teardown hygiene.
Idempotent.  Called at app enable — v1 attached these at load, and a
bare `require' must not mutate the user's global org hooks (the G1
rule); registering here rather than at load also lets the entry's
unregister/re-register pair round-trip the verbs without a re-require.
Teardown of the app's owner detaches everything
\(`jetpacs-teardown-functions', arity (OWNER))."
  (if (not glasspane-clock-enabled)
      ;; A live flag flip retires only legacy identities.  The canonical
      ;; upstream owner may already occupy the durable names.
      (glasspane-clock-remove-hooks)
    ;; Downstream rollback is allowed to disable the upstream integration;
    ;; the upstream module never reaches back into this application.
    (jetpacs-org-clock-unregister)
    ;; :any-surface — D1 GLOBAL verbs, deliberately: a durable tap
    ;; (ttl 3600, the dead-Emacs case this notification exists for)
    ;; replays during SYNCING, before READY re-claims the root.
    (with-jetpacs-owner "glasspane"
      (jetpacs-defaction "org.clock.out" #'glasspane-clock--on-out
                         :any-surface t
                         :doc "Stop the running org clock.")
      (jetpacs-defaction "org.clock.switch" #'glasspane-clock--on-switch
                         :any-surface t
                         :doc "Switch the running clock (no picker yet).")
      (jetpacs-defaction "org.clock.in-last" #'glasspane-clock--on-in-last
                         :any-surface t
                         :doc "Resume the last clocked task."))
    (add-hook 'org-clock-in-hook #'glasspane-clock--assert)
    (add-hook 'org-clock-out-hook #'glasspane-clock--retire)
    (add-hook 'jetpacs-ready-functions #'glasspane-clock--on-ready 90)
    (add-hook 'jetpacs-teardown-functions #'glasspane-clock--on-teardown)
    ;; The app may be enabled mid-session with a clock already running.
    (glasspane-clock--assert))
  t)

(provide 'glasspane-clock)
;;; glasspane-clock.el ends here
