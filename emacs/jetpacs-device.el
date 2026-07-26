;;; jetpacs-device.el --- Device effects: the reminders wrapper -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JA-1 of docs/PLAN-jetpacs-apps.md: the owner-scoped reminders wrapper
;; over `ebp-client-reminders-set' (SPEC 18.6).  The verdict pass
;; promoted this to the poc device module's highest-value shippable
;; piece: the Companion half is implemented and durable, and a reminder
;; is the one JA-1 capability that works while nobody is looking at the
;; screen.
;;
;; What the rewrite dropped from the poc: the capability NEGOTIATION.
;; SPEC 18.6 makes `owner' REQUIRED and non-empty and gates the method
;; on the `reminders.owner' grant, so the poc's "no capability -> send a
;; global set" fallback guarded an impossibility — there is no method
;; for it to call.  The empty-string default owner dies with it: an
;; ownerless set would let unrelated modules clobber each other, the
;; exact thing 18.6's partitioning exists to prevent.
;;
;; D1 correction that shapes every tap handler (SPEC 14.4): a reminder
;; tap OMITS the surface/revision/dialog context members — its source
;; identity arrives in Companion-injected `args' (`:owner',
;; `:reminder_id').  A handler that re-pushes derives the surface from
;; that owner; the zero-arg push is wrong here twice over.
;;
;; Bookkeeping is session-local and mirrors only what the Companion
;; CONFIRMED: the device's sets are device-lifetime durable, so an empty
;; mirror after an Emacs restart does not mean nothing is armed.

;;; Code:

(require 'cl-lib)
(require 'ebp)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)

(defgroup jetpacs-device nil
  "Device-side effects driven from Emacs."
  :group 'jetpacs)

(defvar jetpacs-device--reminder-sets (make-hash-table :test #'equal)
  "OWNER -> (:reminders VECTOR :count N), the last CONFIRMED set.
Session-local mirror; the Companion's durable sets outlive it.")

(defvar jetpacs-device--reminders-gen (make-hash-table :test #'equal)
  "OWNER -> generation counter; guards the mirror against a stale
confirmation overtaking a newer one on crossed responses.")

(defun jetpacs-device-reset ()
  "Clear the session-local device bookkeeping (test teardown seam)."
  (clrhash jetpacs-device--reminder-sets)
  (clrhash jetpacs-device--reminders-gen))

(defun jetpacs-device--reminder-check (reminder)
  "Validate REMINDER (SPEC 18.6) and return a normalized copy.
The copy is rebuilt through the nil-dropping node funnel, so an
explicit nil member never reaches jsonrpc (a literal (:body nil)
would serialize as \"body\":{}).  Error messages name the field and
the rule — never the :title/:body values (SPEC 23.3)."
  (unless (and (consp reminder) (keywordp (car reminder)))
    (error "jetpacs: a reminder must be a keyword plist (SPEC 18.6)"))
  (cl-loop for (k _v) on reminder by #'cddr
           unless (memq k '(:id :title :body :at_ms :on_tap))
           do (error "jetpacs: unknown reminder member %s (18.6 is closed)" k))
  (let ((id (plist-get reminder :id))
        (title (plist-get reminder :title))
        (body (plist-get reminder :body))
        (at-ms (plist-get reminder :at_ms))
        (tap (plist-get reminder :on_tap)))
    (unless (and (stringp id) (jetpacs--identifier-p id))
      (error "jetpacs: reminder :id must be a SPEC 4.4 identifier"))
    (unless (and (stringp title) (not (string-empty-p title)))
      (error "jetpacs: reminder :title must be a non-empty string"))
    (when (and body (not (stringp body)))
      (error "jetpacs: reminder :body must be a string"))
    (unless (and (integerp at-ms) (>= at-ms 0))
      (error (concat "jetpacs: reminder :at_ms must be a non-negative "
                     "INTEGER of epoch millis — floats reject the whole "
                     "set on the wire; use (round (* 1000 (float-time)))")))
    ;; The SPEC 4.2 ceiling too: an over-2^53 integer is content-invalid.
    (jetpacs--check-integer at-ms ":at_ms" 0 nil)
    (when tap
      (jetpacs--check-descriptor tap ":on_tap")
      (unless (plist-member tap :action)
        (error "jetpacs: reminder :on_tap must be a remote action, not a builtin (SPEC 18.6)"))
      (let ((args (plist-get tap :args)))
        (when (or (plist-member args :owner) (plist-member args :reminder_id))
          (error "jetpacs: :on_tap args must not author :owner/:reminder_id — the Companion injects them (SPEC 18.6)")))
      (when (plist-member tap :capture_fields)
        (error "jetpacs: :capture_fields is surface/dialog-scoped; invalid in a reminder :on_tap (SPEC 14.5)"))
      ;; SPEC 18.6 routes a tap through Section 14's normal pipeline using
      ;; the AUTHORED offline policy, so 14.1's wake gate governs here —
      ;; and this path never touches the shell's document gate.
      (jetpacs--gate-descriptor-policy tap)
      (let ((action (plist-get tap :action)))
        (when (and (stringp action)
                   (not (gethash action jetpacs-action-handlers)))
          (display-warning
           'jetpacs
           (format "reminder :on_tap action %S is not registered; a tap will be rejected until it is"
                   action)
           :warning))))
    (jetpacs--node nil :id id :title title :body body :at_ms at-ms
                   :on_tap tap)))

(cl-defun jetpacs-reminders-set (reminders &key owner callback)
  "Replace OWNER's reminder set on the device (SPEC 18.6).
REMINDERS is a list or vector of reminder plists
\(:id ID :title S :at_ms MS [:body S] [:on_tap remote-ACTION]); nil or
empty clears the owner's set.  OWNER defaults from
`with-jetpacs-owner' context and MUST be a valid owner name — it is
also the app surface a tap handler re-pushes.  Signals on invalid
input, a missing owner, no client, or the ungranted capability; the
send itself is asynchronous and D2-safe.

CALLBACK receives (COUNT ERROR) — COUNT the owner's accepted total
after replacement.  Acceptance is ONLY the callback's (COUNT nil);
the return value is the wire id, or nil when the W10 sender ceiling
refused — in that case the callback already saw the local 1401 and
nothing reached the wire.

Legal from SYNCING on (the method's states are S,R), so this is not
gated on `jetpacs-connected-p'."
  (let* ((owner (or owner jetpacs-current-owner))
         (normalized '()))
    (unless (jetpacs--valid-owner-p owner)
      (error "jetpacs: reminders need a valid owner (with-jetpacs-owner or :owner)"))
    (let ((seen (make-hash-table :test #'equal)))
      (dolist (r (append reminders nil))
        (let ((n (jetpacs-device--reminder-check r)))
          (when (gethash (plist-get n :id) seen)
            (error "jetpacs: duplicate reminder :id %S in one set (SPEC 18.6)"
                   (plist-get n :id)))
          (puthash (plist-get n :id) t seen)
          (push n normalized))))
    (let* ((client (jetpacs-client-or-error))
           (vec (vconcat (nreverse normalized)))
           ;; The grant check runs BEFORE the generation bump: an error
           ;; between bump and send would orphan an IN-FLIGHT set's
           ;; confirmation (the gen guard would reject it as stale).
           (gen (progn
                  (unless (jetpacs-granted-p "reminders.owner" client)
                    (error "jetpacs: reminders.set requires the ungranted \"reminders.owner\" capability"))
                  (cl-incf (gethash owner jetpacs-device--reminders-gen 0)))))
      (puthash owner gen jetpacs-device--reminders-gen)
      (ebp-client-reminders-set
       client owner vec
       :callback
       (lambda (count err)
         (if err
             ;; Owner + code + kind/reason only: the wire :message and
             ;; the reminder titles stay out of logs (SPEC 23.3).
             (message "jetpacs: reminders.set (%s) failed: code %s (%s)"
                      owner (plist-get err :code)
                      (or (plist-get (plist-get err :data) :reason)
                          (plist-get (plist-get err :data) :kind)
                          "?"))
           ;; Adopt into the mirror only when no newer set superseded
           ;; this one while it was in flight.
           (when (eql gen (gethash owner jetpacs-device--reminders-gen))
             (if (zerop (length vec))
                 (remhash owner jetpacs-device--reminder-sets)
               (puthash owner (list :reminders vec :count count)
                        jetpacs-device--reminder-sets))))
         (when callback (funcall callback count err)))))))

(defun jetpacs-reminders (&optional owner)
  "The last set the Companion CONFIRMED for OWNER in THIS session.
A plist (:reminders VECTOR :count N), or nil.  nil does NOT mean the
device holds nothing: its sets are device-lifetime durable and this
mirror is session-local — never use it to skip a clear."
  (when-let* ((owner (or owner jetpacs-current-owner)))
    (gethash owner jetpacs-device--reminder-sets)))

(defun jetpacs-reminders-clear (&optional owner callback)
  "Clear OWNER's reminder set on the device (an empty replace-set)."
  (jetpacs-reminders-set nil :owner owner :callback callback))

(defun jetpacs-device--on-teardown (owner)
  "Sweep OWNER's local reminder bookkeeping (JA-2 teardown hook).
LOCAL only, deliberately: the device's reminder sets are durable by
design and survive an owner teardown — clearing them there is a
product decision the caller makes explicitly via
`jetpacs-reminders-clear' BEFORE tearing down, not a side effect."
  ;; The GENERATION counter deliberately survives: it is monotonic per
  ;; owner for the SESSION, not per set — resetting it on re-registration
  ;; let a stale in-flight confirmation overwrite a newer one while the
  ;; guard reported success.
  (remhash owner jetpacs-device--reminder-sets))

(add-hook 'jetpacs-teardown-functions #'jetpacs-device--on-teardown)

(provide 'jetpacs-device)
;;; jetpacs-device.el ends here
