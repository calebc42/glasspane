;;; jetpacs-floor-test.el --- JC-0 floor exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JC-0 exit-gate suite (docs/SPEC-JC-0-floor.md section 7):
;; ownership, the defaction shim driven through ebp's real
;; `ebp-client--handle-event-action', and the four `jetpacs-shell-push'
;; runtime gates against a deliberately under-advertised welcome fixture
;; (the 8-type Core Node Set — the reference defconst cannot witness the
;; gate, which is the point).

;;; Code:

(require 'ert)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)

(defconst jetpacs-floor-test--core-types
  ["text" "row" "column" "box" "spacer" "divider" "button" "text_input"]
  "The under-advertised fixture: exactly the SPEC 16.2 Core Node Set.")

(cl-defun jetpacs-floor-test--client (&key granted profiles limits)
  "A stub READY client with an under-advertised app profile."
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jetpacs-floor-receipts"))))
    (setf (ebp-client-state client) 'ready
          (ebp-client-granted client) (or granted ["theme"])
          (ebp-client-profiles client)
          (or profiles
              `(:app (:node_types ,jetpacs-floor-test--core-types
                      :builtins ["view.switch"]
                      :features [])))
          (ebp-client-limits client) (or limits '(:max_frame_bytes 4194304)))
    client))

(defmacro jetpacs-floor-test--with-client (spec &rest body)
  "Attach a fresh stub client as VAR, run BODY, always detach and reset.
SPEC is (VAR . CLIENT-KEYS)."
  (declare (indent 1))
  (let ((var (car spec)))
    `(let ((,var (jetpacs-floor-test--client ,@(cdr spec))))
       (unwind-protect
           (progn (jetpacs-attach ,var) ,@body)
         (jetpacs-detach)
         (jetpacs-test-reset-state)
         (setq jetpacs-shell--roots nil
               jetpacs-shell--repush-pending nil)
         (when (timerp jetpacs-shell--repush-timer)
           (cancel-timer jetpacs-shell--repush-timer)
           (setq jetpacs-shell--repush-timer nil))))))

(defun jetpacs-floor-test--event (event-id &rest over)
  "A valid surface event.action params plist, OVER plist overriding."
  (append over
          (list :event_id event-id :action "demo.count"
                :args '(:n 3 :flag :json-false)
                :surface "app:demo" :revision_seen 41
                :occurred_at_ms 1784700000000)))

;;;; Ownership

(ert-deftest jetpacs-floor-ownership-claim-and-clash ()
  (clrhash jetpacs--registrations)
  (with-jetpacs-owner "appa"
    (should (equal (jetpacs--claim "action" "a.x") "a.x"))
    ;; Same-owner re-claim is silent.
    (jetpacs--claim "action" "a.x"))
  (with-jetpacs-owner "appb"
    ;; Cross-owner clash warns by default and the newer owner wins…
    (jetpacs--claim "action" "a.x")
    (should (equal (jetpacs--owner-of "action" "a.x") "appb"))
    ;; …and errors under strict namespaces.
    (with-jetpacs-owner "appa"
      (let ((jetpacs-strict-namespaces t))
        (should-error (jetpacs--claim "action" "a.x")))))
  (should (equal (jetpacs--owned-names "action" "appb") '("a.x")))
  (jetpacs--unclaim "action" "a.x")
  (should-not (jetpacs--owner-of "action" "a.x")))

(ert-deftest jetpacs-floor-owner-is-a-wire-identifier ()
  "Decision D1: an owner names app:<owner>, so it must be a SPEC 4.4
name; the failure is registration-time, never a push-time 1201."
  (should-error (with-jetpacs-owner "has:colon" (jetpacs--claim "x" "y")))
  (should-error (with-jetpacs-owner "" (jetpacs--claim "x" "y")))
  (should-error (with-jetpacs-owner nil (jetpacs--claim "x" "y"))))

;;;; The defaction shim, through ebp's real event.action server

(ert-deftest jetpacs-floor-shim-statuses-and-duplicate ()
  (jetpacs-floor-test--with-client (client)
    (let ((seen nil) (runs 0))
      (with-jetpacs-owner "demo"
        (jetpacs-defaction "demo.count"
                           (lambda (args params)
                             (cl-incf runs)
                             (setq seen (list args params
                                              (jetpacs-in-action-p)))
                             'accepted)))
      ;; accepted commits the receipt…
      (should (equal (ebp-client--handle-event-action
                      client (jetpacs-floor-test--event (make-string 32 ?a)))
                     '(:status "accepted")))
      ;; …the handler saw decoded args AND the full params (plan 2.5-2)…
      (pcase-let ((`(,args ,params ,in-handler) seen))
        (should (equal (plist-get args :n) 3))
        (should (eq (plist-get args :flag) :json-false))
        (should (equal (plist-get params :event_id) (make-string 32 ?a)))
        (should (equal (plist-get params :surface) "app:demo"))
        (should (equal (plist-get params :revision_seen) 41))
        (should in-handler))
      (should-not (jetpacs-in-action-p))
      ;; …and a repeated EventId answers duplicate WITHOUT the handler.
      (should (equal (ebp-client--handle-event-action
                      client (jetpacs-floor-test--event (make-string 32 ?a)))
                     '(:status "duplicate")))
      (should (= runs 1)))
    ;; stale and rejected pass through untouched.
    (with-jetpacs-owner "demo"
      (jetpacs-defaction "demo.stale" (lambda (_a _p) 'stale))
      (jetpacs-defaction "demo.reject" (lambda (_a _p) 'rejected)))
    (should (equal (ebp-client--handle-event-action
                    client (jetpacs-floor-test--event
                            (make-string 32 ?b) :action "demo.stale"))
                   '(:status "stale")))
    (should (equal (ebp-client--handle-event-action
                    client (jetpacs-floor-test--event
                            (make-string 32 ?c) :action "demo.reject"))
                   '(:status "rejected")))))

(ert-deftest jetpacs-floor-shim-nonstatus-error-and-quit ()
  "Decision Q3: a non-status return, an error, and a quit all answer
rejected — never a durable blanket-accept, never a bare -32603."
  (jetpacs-floor-test--with-client (client)
    (with-jetpacs-owner "demo"
      (jetpacs-defaction "demo.weird" (lambda (_a _p) "done!"))
      (jetpacs-defaction "demo.boom" (lambda (_a _p) (error "kaboom")))
      (jetpacs-defaction "demo.quit" (lambda (_a _p) (signal 'quit nil))))
    (let ((warning-minimum-log-level :emergency))
      (dolist (action '("demo.weird" "demo.boom" "demo.quit"))
        (should (equal (ebp-client--handle-event-action
                        client (jetpacs-floor-test--event
                                (concat (make-string 30 ?d)
                                        (format "%02x" (length action)))
                                :action action))
                       '(:status "rejected")))))))

(ert-deftest jetpacs-floor-attach-replays-staged-actions ()
  "The structural crux: registrations are load-time, allowlists are
per-client; attach must replay or every event answers rejected."
  (with-jetpacs-owner "demo"
    (jetpacs-defaction "demo.early" (lambda (_a _p) 'accepted)))
  (jetpacs-floor-test--with-client (client)   ; attach happens inside
    (should (gethash "demo.early" (ebp-client-actions client)))
    (should (equal (ebp-client--handle-event-action
                    client (jetpacs-floor-test--event
                            (make-string 32 ?e) :action "demo.early"))
                   '(:status "accepted"))))
  (jetpacs-undefaction "demo.early"))

(ert-deftest jetpacs-floor-boundary-no-handler-registration ()
  "The floor registers actions, never protocol method handlers."
  (jetpacs-floor-test--with-client (client)
    (let ((bare (ebp-client-create
                 :receipt-file (make-temp-file "jetpacs-floor-bare"))))
      (should (= (hash-table-count (ebp-client-handlers client))
                 (hash-table-count (ebp-client-handlers bare)))))))

(ert-deftest jetpacs-floor-event-stale-p ()
  "SPEC 14.5 staleness is measured against the newest CONFIRMED-applied
revision.  `ebp-client-revisions' cannot serve: it claims floor+1 at
SEND time and never rolls back, so one refused push would otherwise
make every later tap on that surface stale forever."
  (jetpacs-floor-test--with-client (client)
    (clrhash jetpacs--applied-revisions)
    ;; Nothing confirmed yet -> nothing is stale.
    (should-not (jetpacs-event-stale-p '(:surface "app:demo" :revision_seen 3)))
    ;; A confirmed apply raises the bar.
    (jetpacs-shell--confirm-applied "app:demo" 5 "applied" nil)
    (should (jetpacs-event-stale-p '(:surface "app:demo" :revision_seen 3)))
    (should-not (jetpacs-event-stale-p '(:surface "app:demo" :revision_seen 5)))
    ;; A REFUSED push must not: revision 9 was claimed but never applied.
    (jetpacs-shell--confirm-applied "app:demo" 9 nil '(:code 1201))
    (should-not (jetpacs-event-stale-p '(:surface "app:demo" :revision_seen 5)))
    ;; A `stale' result is not an apply either (SPEC 13.2 idempotency).
    (jetpacs-shell--confirm-applied "app:demo" 9 "stale" nil)
    (should-not (jetpacs-event-stale-p '(:surface "app:demo" :revision_seen 5)))
    ;; A dialog event has no surface/revision context: never stale.
    (should-not (jetpacs-event-stale-p '(:dialog_id "d1")))))

(ert-deftest jetpacs-floor-applied-revisions-seed-from-welcome ()
  "A8 P1 (RESEARCH-A8 5.2): welcome floors ARE confirmed applies.
The table is in-memory and was written only on an `applied' result, so
after a process restart it was empty, `jetpacs-event-stale-p' answered
\"not stale\" for every surface, and each event replayed from the
durable queue dispatched against a snapshot revisions old.  The seed
adopts the welcome floors; the Companion is the authority, so seeding
REPLACES — a leftover entry above a legitimately fallen floor (pairing
wipe) must not survive."
  (jetpacs-floor-test--with-client (client)
    (setf (ebp-client-surfaces client)
          '(:app:demo (:revision 60 :present t)
            :app:gone (:revision 7 :present nil)
            :app:junk (:revision "x" :present t)))
    ;; The cold-start hole, pinned: before the seed nothing is stale,
    ;; even 18 revisions behind the floor the Companion reported.
    (puthash "app:zombie" 99 jetpacs--applied-revisions)
    (should-not (jetpacs-event-stale-p
                 '(:surface "app:demo" :revision_seen 42)))
    (jetpacs--seed-applied-revisions client)
    ;; Below the floor -> stale; at the floor -> fresh.
    (should (jetpacs-event-stale-p
             '(:surface "app:demo" :revision_seen 42)))
    (should-not (jetpacs-event-stale-p
                 '(:surface "app:demo" :revision_seen 60)))
    ;; A tombstone floor participates: the removal outran the event.
    (should (jetpacs-event-stale-p
             '(:surface "app:gone" :revision_seen 3)))
    ;; Replace-not-max: the prior session's leftover is gone.
    (should-not (gethash "app:zombie" jetpacs--applied-revisions))
    ;; A malformed floor seeds nothing rather than poisoning stale-p.
    (should-not (gethash "app:junk" jetpacs--applied-revisions))
    ;; A surface the Companion never reported stays not-stale.
    (should-not (jetpacs-event-stale-p
                 '(:surface "app:new" :revision_seen 0)))))

(defun jetpacs-floor-test--exploding-before-replay-member (_client)
  "A `jetpacs-before-replay-functions' member that always signals."
  (error "floor probe: the before-replay member exploded"))

(ert-deftest jetpacs-floor-before-replay-isolates-a-failing-member ()
  "A signalling subscriber must not take the SPEC 10.3 barrier with it.
`ebp-client--on-welcome' calls the before-replay seam BARE: a signal
escaping it skipped the `queue.replay' request entirely and left the
session SYNCING forever — no replay, no READY, no recovery short of a
reconnect.  The probe is pinned at depth -100 so it runs FIRST, ahead
of the shell's required-root push.

The seed is the other half: it is hard-coded into
`jetpacs--before-replay' AHEAD of the hook, by structure and not by
depth, so no member can sort in front of the kernel state the members
themselves read."
  (jetpacs-floor-test--with-client (client)
    (setf (ebp-client-surfaces client)
          '(:app:demo (:revision 60 :present t)))
    (add-hook 'jetpacs-before-replay-functions
              #'jetpacs-floor-test--exploding-before-replay-member -100)
    (unwind-protect
        ;; Escaping here IS the failure — no `should-error' wrapper.
        (let ((inhibit-message t))
          (jetpacs--before-replay client))
      (remove-hook 'jetpacs-before-replay-functions
                   #'jetpacs-floor-test--exploding-before-replay-member))
    ;; …and the seed still landed: below the floor is stale, at it fresh.
    (should (jetpacs-event-stale-p
             '(:surface "app:demo" :revision_seen 42)))
    (should-not (jetpacs-event-stale-p
                 '(:surface "app:demo" :revision_seen 60)))))

(ert-deftest jetpacs-floor-replayed-event-against-old-snapshot-is-stale ()
  "A8 P1 end to end: the barrier seed reaches a real replayed dispatch.
`jetpacs--before-replay' is what `jetpacs-connect' installs; SPEC 10.3
runs it at step 3, before `queue.replay' (step 4) delivers retained
events, so a handler that opts into `jetpacs-event-stale-p' must see
the seeded floors by then.  Without the seed the first event — queued
against revision 42 before the restart — dispatched `accepted' and the
handler indexed an 18-revision-old snapshot."
  (jetpacs-floor-test--with-client (client)
    (setf (ebp-client-surfaces client) '(:app:demo (:revision 60 :present t)))
    (jetpacs--before-replay client)
    (with-jetpacs-owner "demo"
      (jetpacs-defaction "a8.visit"
                         (lambda (_args params)
                           (if (jetpacs-event-stale-p params)
                               'stale
                             'accepted))))
    ;; The replayed event, queued against the pre-restart snapshot.
    ;; Event ids are the SPEC 4.4 hex grammar — fillers must be hex digits.
    (should (equal (ebp-client--handle-event-action
                    client (jetpacs-floor-test--event
                            (make-string 32 ?d)
                            :action "a8.visit" :revision_seen 42))
                   '(:status "stale")))
    ;; An event against the current floor dispatches normally.
    (should (equal (ebp-client--handle-event-action
                    client (jetpacs-floor-test--event
                            (make-string 32 ?e)
                            :action "a8.visit" :revision_seen 60))
                   '(:status "accepted")))
    (jetpacs-undefaction "a8.visit")))

(ert-deftest jetpacs-floor-syncing-push-drains-at-ready ()
  "A replayed handler's deferred re-push must survive the SYNCING gate.
SPEC 10.3 step 4 delivers replayed events while the session is still
SYNCING; a D2 handler accepts and defers its re-push, the deferral
fires before READY, and `jetpacs-shell-push''s gate refuses it.
Dropping it silently left the device on the pre-event snapshot until
the user's NEXT tap — caught on hardware by smoke-a8-coldstart.  The
refused push now queues in `jetpacs-shell--repush-pending' and
`jetpacs-shell--on-ready' drains it."
  (jetpacs-floor-test--with-client (client)
    (let ((pushed '()))
      (cl-letf (((symbol-function 'ebp-client-surface-update)
                 (cl-function
                  (lambda (_client surface _spec &key &allow-other-keys)
                    (push surface pushed)
                    7))))
        (with-jetpacs-owner "a8drain"
          (jetpacs-shell-define-root "a8drain"
                                     (lambda ()
                                       (jetpacs-text "drain me"))))
        ;; The replay window: authenticated but not yet READY.
        (setf (ebp-client-state client) 'syncing)
        (should-not (jetpacs-shell-push "app:a8drain"))
        (should-not pushed)
        (should (member "app:a8drain" jetpacs-shell--repush-pending))
        ;; A one-off :spec push refused in SYNCING requeues the SURFACE,
        ;; not the payload — the drain re-renders through the registered
        ;; builder — and dedupes rather than queueing twice.
        (should-not (jetpacs-shell-push "app:a8drain"
                                        :spec '(:t "text" :text "x")))
        (should (= 1 (cl-count "app:a8drain" jetpacs-shell--repush-pending
                               :test #'equal)))
        ;; READY: the drain pushes through the registered builder.
        (setf (ebp-client-state client) 'ready)
        (jetpacs-shell--on-ready client)
        (should (equal pushed '("app:a8drain")))
        (should-not jetpacs-shell--repush-pending)
        ;; Fully disconnected pushes stay dropped (the barrier owns those).
        (setf (ebp-client-state client) 'closed)
        (should-not (jetpacs-shell-push "app:a8drain"))
        (should-not jetpacs-shell--repush-pending))
      ;; Bare unclaim: `remove-root' would queue a tombstone for a
      ;; surface no later floor test ever flushes.
      (jetpacs--unclaim "surface" "app:a8drain"))))

(ert-deftest jetpacs-floor-state-fanout ()
  (jetpacs-floor-test--with-client (client)
    (let (got)
      (jetpacs-on-state-change "title" (lambda (v) (push v got)) "app:demo")
      (jetpacs-on-state-change "doomed" (lambda (_v) (error "bad handler"))
                               "app:demo")
      (jetpacs--on-state-changed client "app:demo" 7 "title" "draft")
      ;; A broken sibling callback must not break the fan-out.
      (jetpacs--on-state-changed client "app:demo" 7 "doomed" "x")
      (jetpacs--on-state-changed client "app:demo" 8 "title" "draft2")
      (should (equal got '("draft2" "draft")))
      (jetpacs-on-state-change-clear "ti")
      (jetpacs--on-state-changed client "app:demo" 9 "title" "draft3")
      (should (equal got '("draft2" "draft"))))))

(ert-deftest jetpacs-floor-state-keyed-by-surface ()
  "SPEC 14.6 scopes input state to (surface, id).  Under decision D1
every owner has its own surface, so the same widget id in two apps must
NOT collide — the bug bare-id keying would have caused."
  (jetpacs-floor-test--with-client (client)
    (let (a b)
      ;; Both apps use the widget id "title"; each subscribes in its own
      ;; owner scope, so the surface is implied.
      (with-jetpacs-owner "appa"
        (jetpacs-on-state-change "title" (lambda (v) (push v a))))
      (with-jetpacs-owner "appb"
        (jetpacs-on-state-change "title" (lambda (v) (push v b))))
      (jetpacs--on-state-changed client "app:appa" 1 "title" "from-a")
      (jetpacs--on-state-changed client "app:appb" 1 "title" "from-b")
      (should (equal a '("from-a")))
      (should (equal b '("from-b")))
      ;; A clear scoped to one surface leaves the other subscribed.
      (jetpacs-on-state-change-clear "title" "app:appa")
      (jetpacs--on-state-changed client "app:appa" 2 "title" "again-a")
      (jetpacs--on-state-changed client "app:appb" 2 "title" "again-b")
      (should (equal a '("from-a")))
      (should (equal b '("again-b" "from-b"))))))

;;;; The push gates

(defmacro jetpacs-floor-test--recording-push (records &rest body)
  "Run BODY with `ebp-client-surface-update' recording into RECORDS.
Each record is (SURFACE SPEC KEYS); the recorder returns revision 42."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'ebp-client-surface-update)
              (lambda (_client surface spec &rest keys)
                (push (list surface spec keys) ,records)
                42)))
     ,@body))

(ert-deftest jetpacs-floor-gate-node-types-live-welcome ()
  "Plan 2.5-1: the gate runs against the LIVE advertised set; the
reference defconst passes the same spec, proving it cannot witness."
  (jetpacs-floor-test--with-client (client)
    (let ((sent nil)
          (spec (jetpacs-column
                 (jetpacs-text "hi")
                 '(:t "card" :children [(:t "text" :text "x")]))))
      ;; The maximal reference profile accepts it…
      (should (jetpacs-check-profile spec 'app))
      ;; …the live gate refuses it BEFORE any send.
      (jetpacs-floor-test--recording-push sent
        (should-error (jetpacs-shell-push "app:demo" :spec spec))
        (should-not sent)
        ;; A pure-core spec passes and sends.
        (should (= (jetpacs-shell-push "app:demo"
                                       :spec (jetpacs-text "plain"))
                   42))
        (should (= (length sent) 1))))))

(ert-deftest jetpacs-floor-gate-stale-spec-and-builtins ()
  (jetpacs-floor-test--with-client (client)
    (let ((sent nil))
      (jetpacs-floor-test--recording-push sent
        ;; stale_spec is gated like spec (SPEC 13.5)…
        (should-error
         (jetpacs-shell-push "app:demo" :spec (jetpacs-text "a")
                             :stale-spec '(:t "card")))
        ;; …an unadvertised builtin refuses (SPEC 10.2)…
        (should-error
         (jetpacs-shell-push
          "app:demo"
          :spec '(:t "button" :label "b" :on_tap (:builtin "clipboard.copy"
                                                  :text "x"))))
        (should-not sent)
        ;; …and a stateful node is stripped from the sent stale_spec.
        (jetpacs-shell-push
         "app:demo" :spec (jetpacs-text "a")
         :stale-spec (jetpacs-column (jetpacs-text "stale")
                                     '(:t "text_input" :id "ti")))
        (let* ((keys (nth 2 (car sent)))
               (stale (plist-get keys :stale-spec)))
          (should stale)
          (should (member "text" (jetpacs--collect-node-types stale '())))
          (should-not (member "text_input"
                              (jetpacs--collect-node-types stale '()))))))))

(ert-deftest jetpacs-floor-gate-missing-profile-and-capability ()
  (jetpacs-floor-test--with-client
      (client :profiles `(:app (:node_types ,jetpacs-floor-test--core-types
                                :builtins [] :features [])
                          :notification (:node_types ["text"]
                                         :builtins [] :features [])))
    (let ((sent nil))
      (jetpacs-floor-test--recording-push sent
        ;; SPEC 10.2: a missing profile is NOT support for everything.
        (should-error (jetpacs-shell-push "widget:w1"
                                          :spec (jetpacs-text "x")))
        ;; An advertised profile without the granted capability refuses.
        (should-error (jetpacs-shell-push "notification:n1"
                                          :spec (jetpacs-text "x")))
        (should-not sent)))))

(ert-deftest jetpacs-floor-gate-current-view-discipline ()
  "SPEC 13.4: current_view only for a multi-view app spec."
  (jetpacs-floor-test--with-client (client)
    (let ((sent nil))
      (jetpacs-floor-test--recording-push sent
        (jetpacs-shell-push "app:demo" :spec (jetpacs-text "single")
                            :current-view "list")
        (should (null (plist-get (nth 2 (car sent)) :current-view)))
        (jetpacs-shell-push
         "app:demo"
         :spec (jetpacs-multi-view `(("list" . ,(jetpacs-text "l"))
                                     ("detail" . ,(jetpacs-text "d")))
                                   "list")
         :current-view "detail")
        (should (equal (plist-get (nth 2 (car sent)) :current-view)
                       "detail"))
        (should (= (length sent) 2))))))

(ert-deftest jetpacs-floor-gate-wake-amendment-85 ()
  (let ((spec '(:t "button" :label "b"
                :on_tap (:action "a.b" :when_offline "wake" :ttl_s 60))))
    ;; Without the grant: refused before any send.
    (jetpacs-floor-test--with-client (client)
      (let ((sent nil))
        (jetpacs-floor-test--recording-push sent
          (should-error (jetpacs-shell-push "app:demo" :spec spec))
          (should-not sent))))
    ;; With the grant: sent.
    (jetpacs-floor-test--with-client (client :granted ["offline.wake"])
      (let ((sent nil))
        (jetpacs-floor-test--recording-push sent
          (should (= (jetpacs-shell-push "app:demo" :spec spec) 42)))))))

(ert-deftest jetpacs-floor-gate-editor-bytes-amendment-84 ()
  (jetpacs-floor-test--with-client
      (client :profiles '(:app (:node_types ["editor"] :builtins []
                                :features []))
              :limits '(:max_editor_bytes 16))
    (let ((sent nil))
      (jetpacs-floor-test--recording-push sent
        ;; A synchronized editor past the bound is refused…
        (should-error
         (jetpacs-shell-push
          "app:demo"
          :spec `(:t "editor" :id "e" :document "doc:1"
                  :value ,(make-string 20 ?x))))
        (should-not sent)
        ;; …a local editor (no :document) is not this gate's business.
        (should (= (jetpacs-shell-push
                    "app:demo"
                    :spec `(:t "editor" :id "e"
                            :value ,(make-string 20 ?x)))
                   42))))))

(ert-deftest jetpacs-floor-push-d1-resolution-and-hook ()
  "Decision D1: zero-arg pushes the current owner's surface; a bare
owner argument maps to app:<owner>; the after-push hook runs on the
success path."
  (jetpacs-floor-test--with-client (client)
    (setf (ebp-client-profiles client)
          `(:app (:node_types ,jetpacs-floor-test--core-types
                  :builtins [] :features [])))
    (let ((sent nil) (hooked 0))
      (jetpacs-floor-test--recording-push sent
        (with-jetpacs-owner "grocy"
          (jetpacs-shell-define-root "grocy"
                                     (lambda () (jetpacs-text "hello"))))
        (let ((hook (lambda () (cl-incf hooked))))
          (add-hook 'jetpacs-shell-after-push-hook hook)
          (unwind-protect
              (progn
                ;; Bare owner resolves to app:grocy.
                (should (= (jetpacs-shell-push "grocy") 42))
                (should (equal (caar sent) "app:grocy"))
                ;; Zero-arg inside the owner scope hits the same surface.
                (with-jetpacs-owner "grocy"
                  (should (= (jetpacs-shell-push) 42)))
                (should (equal (caar sent) "app:grocy"))
                ;; Zero-arg with no root registered elsewhere: nil, no send.
                (should-not (jetpacs-shell-push "app:other"))
                (should (= (length sent) 2))
                (should (= hooked 2)))
            (remove-hook 'jetpacs-shell-after-push-hook hook)))))))

(ert-deftest jetpacs-floor-before-replay-pushes-required ()
  "SPEC 10.3 step 3: required roots push during `syncing', bypassing
the READY guard; optional roots wait."
  (jetpacs-floor-test--with-client (client)
    (setf (ebp-client-state client) 'syncing)
    (let ((sent nil))
      (jetpacs-floor-test--recording-push sent
        (with-jetpacs-owner "grocy"
          (jetpacs-shell-define-root "grocy" (lambda () (jetpacs-text "r"))
                                     :required t))
        (with-jetpacs-owner "extra"
          (jetpacs-shell-define-root "extra" (lambda () (jetpacs-text "o"))))
        ;; Not READY: a normal push is a silent no-op…
        (should-not (jetpacs-shell-push "grocy"))
        (should-not sent)
        ;; …the barrier path pushes exactly the required roots.
        (jetpacs-shell--before-replay client)
        (should (equal (mapcar #'car sent) '("app:grocy")))))))

(ert-deftest jetpacs-floor-snackbar-scaffold-and-requeue ()
  ;; The toast degrade now rides the GATED jetpacs-toast (JA-2/B7), so
  ;; the fixture must grant presentation.toast for the degrade branch.
  (jetpacs-floor-test--with-client
      (client :granted ["theme" "presentation.toast"]
              :profiles '(:app (:node_types ["text" "scaffold" "column"]
                                :builtins [] :features [])))
    (let ((sent nil) (toasts nil))
      (cl-letf (((symbol-function 'ebp-client-toast)
                 (lambda (_c text &rest _) (push text toasts))))
        (jetpacs-floor-test--recording-push sent
          ;; A scaffold root carries the snackbar inline; the slot drains.
          (jetpacs-shell-notify "saved" "app:demo")
          (jetpacs-shell-push
           "app:demo" :spec '(:t "scaffold" :body (:t "text" :text "b")))
          (should (equal (plist-get (nth 1 (car sent)) :snackbar) "saved"))
          (should-not (gethash "app:demo" jetpacs-shell--snackbars))
          (should-not toasts)
          ;; A non-scaffold root degrades to a toast.
          (jetpacs-shell-notify "toasted" "app:demo")
          (jetpacs-shell-push "app:demo" :spec '(:t "text" :text "t"))
          (should (equal toasts '("toasted")))
          ;; A failed push requeues the snackbar for the next one.
          (jetpacs-shell-notify "kept" "app:demo")
          (should-error (jetpacs-shell-push
                         "app:demo" :spec '(:t "card")))
          (should (equal (gethash "app:demo" jetpacs-shell--snackbars) "kept"))))))
  ;; Ungranted: the degrade drops silently and the push still succeeds.
  (jetpacs-floor-test--with-client
      (client :profiles '(:app (:node_types ["text" "scaffold" "column"]
                                :builtins [] :features [])))
    (let ((sent nil) (toasts nil))
      (cl-letf (((symbol-function 'ebp-client-toast)
                 (lambda (_c text &rest _) (push text toasts))))
        (jetpacs-floor-test--recording-push sent
          (jetpacs-shell-notify "dropped" "app:demo")
          (jetpacs-shell-push "app:demo" :spec '(:t "text" :text "t"))
          (should (= (length sent) 1))
          (should-not toasts)
          (should-not (gethash "app:demo" jetpacs-shell--snackbars)))))))

;;;; JA-2a utilities: toast gate, refused-p, retry-later (B7/B8/B9)

(ert-deftest jetpacs-floor-toast-gate-and-sanitize ()
  (jetpacs-floor-test--with-client (client)
    (let ((spy nil))
      (cl-letf (((symbol-function 'ebp-client-toast)
                 (cl-function (lambda (_c text &key duration-s)
                                (push (list text duration-s) spy)))))
        ;; Ungranted: silent no-op.
        (should-not (jetpacs-toast "hi"))
        (should-not spy)
        (setf (ebp-client-granted client) ["theme" "presentation.toast"])
        (should (jetpacs-toast "hi" :duration-s 3))
        (should (equal (car spy) '("hi" 3)))
        ;; toast.show is R-only.
        (setf (ebp-client-state client) 'syncing)
        (should-not (jetpacs-toast "hi"))
        (setf (ebp-client-state client) 'ready)
        ;; Raw bytes sanitized on the way out.
        (jetpacs-toast (concat "a" (string #x3FFF80)))
        (should (equal (caar spy) "a�"))
        ;; Validation is loud even when it would be gated off.
        (should-error (jetpacs-toast "x" :duration-s 0))
        (should-error (jetpacs-toast "x" :duration-s 11))
        (should-error (jetpacs-toast 42)))))
  ;; Detached: nil, no error.
  (should-not (jetpacs-toast "hi")))

(ert-deftest jetpacs-floor-refused-p-shape ()
  (should (jetpacs-refused-p '(:code 1401
                               :message "Outstanding requests exhausted"
                               :data (:kind "overloaded")
                               :ebp-local t)))
  ;; E3: a PEER'S 1401 is byte-identical except the tag — 1401 is a
  ;; MANDATORY response code (max_dialogs), and will-retry semantics
  ;; belong only to the local ceiling.  Untagged is NOT refused.
  (should-not (jetpacs-refused-p '(:code 1401
                                   :message "Outstanding requests exhausted"
                                   :data (:kind "overloaded"))))
  (should-not (jetpacs-refused-p nil))
  (should-not (jetpacs-refused-p '(:code 1201 :data (:kind "content-invalid"))))
  (should-not (jetpacs-refused-p '(:code 1401 :data (:kind "something-else"))))
  (should-not (jetpacs-refused-p '(:code 1401))))

(ert-deftest jetpacs-floor-refused-push-requeues ()
  "A W10-refused push with a registered root schedules the debounced
repush; the confirmed floor never rises.  Drives ebp's REAL held branch
— no stubs on any ebp function."
  (jetpacs-floor-test--with-client (client)
    (with-jetpacs-owner "grocy"
      (jetpacs-shell-define-root "grocy"
                                 (lambda () '(:t "text" :text "r"))))
    (setf (ebp-client-outstanding client) ebp-overload-hold)
    (let ((captured :none))
      (with-jetpacs-owner "grocy"
        (jetpacs-shell-push "grocy"
                            :callback (lambda (_status error)
                                        (setq captured error))))
      ;; The refusal concluded synchronously.
      (should (jetpacs-refused-p captured))
      (should (member "app:grocy" jetpacs-shell--repush-pending))
      (should (timerp jetpacs-shell--repush-timer))
      (should-not (gethash "app:grocy" jetpacs--applied-revisions)))))

(ert-deftest jetpacs-floor-retry-later-answers-1500-not-accepted ()
  (jetpacs-floor-test--with-client (client)
    (let ((runs 0))
      (with-jetpacs-owner "demo"
        (jetpacs-defaction "demo.later"
          (lambda (_a _p) (cl-incf runs) (jetpacs-retry-later 30))))
      (unwind-protect
          (let ((eid (make-string 32 ?e)))
            (should-error
             (ebp-client--handle-event-action
              client (jetpacs-floor-test--event eid :action "demo.later"))
             :type 'jsonrpc-error)
            ;; No receipt: not accepted, so the same id runs AGAIN.
            (should-not (gethash eid (ebp-client-receipts client)))
            (should-error
             (ebp-client--handle-event-action
              client (jetpacs-floor-test--event eid :action "demo.later"))
             :type 'jsonrpc-error)
            (should (= runs 2))
            ;; The SPEC 15.3 replay was forced.
            (should (timerp (ebp-client-replay-retry-timer client))))
        (when-let* ((tm (ebp-client-replay-retry-timer client)))
          (cancel-timer tm))))))

(ert-deftest jetpacs-floor-retry-later-outside-handler ()
  "Outside a dispatch it is a plain error, never a wire-shaped one."
  (should (eq 'ok (condition-case _err
                      (jetpacs-retry-later)
                    (jsonrpc-error (ert-fail "signalled jsonrpc-error"))
                    (error 'ok)))))

(ert-deftest jetpacs-floor-gate-features ()
  "SPEC 10.2 mandates gating nodes, builtins AND features; 17.2 makes an
unadvertised image URI form content-invalid and 17.7 does the same for a
registered toolbar identifier."
  (jetpacs-floor-test--with-client
      (client :profiles '(:app (:node_types ["text" "image" "editor" "column"]
                                :builtins []
                                :features ["image.https" "toolbar.org"])))
    (let ((sent nil))
      (jetpacs-floor-test--recording-push sent
        ;; An advertised form passes.
        (should (= (jetpacs-shell-push
                    "app:demo"
                    :spec '(:t "image" :url "https://example.com/a.png"))
                   42))
        ;; data: is NOT advertised here -> refused before the send.
        (should-error (jetpacs-shell-push
                       "app:demo"
                       :spec '(:t "image" :url "data:image/png;base64,AAAA")))
        ;; A registered toolbar identifier must be advertised...
        (should (= (jetpacs-shell-push
                    "app:demo"
                    :spec '(:t "editor" :id "e" :toolbar "org"))
                   42))
        (should-error (jetpacs-shell-push
                       "app:demo"
                       :spec '(:t "editor" :id "e" :toolbar "markdown")))
        ;; ...while an INLINE ToolbarItem array needs no feature.
        (should (= (jetpacs-shell-push
                    "app:demo"
                    :spec '(:t "editor" :id "e"
                            :toolbar [(:label "B" :snippet "**")]))
                   42))
        (should (= (length sent) 3))))))

(ert-deftest jetpacs-floor-gate-notification-meta-descriptors ()
  "18.5 action descriptors live under the OPAQUE `:meta' key, so the
generic walker cannot see them — yet that is the only place 18.5 puts a
descriptor, i.e. exactly where amendment #85's wake gate matters."
  (jetpacs-floor-test--with-client
      (client :granted ["surfaces.notification"]
              :profiles '(:notification (:node_types ["text"]
                                         :builtins [] :features [])))
    (let ((sent nil)
          (spec '(:t nil :body (:t "text" :text "hi")
                  :meta (:actions [(:label "Snooze"
                                    :on_tap (:action "a.snooze"
                                             :when_offline "wake"
                                             :ttl_s 60))]))))
      (jetpacs-floor-test--recording-push sent
        ;; offline.wake ungranted -> the buried descriptor must be caught.
        (should-error (jetpacs-shell-push "notification:n1" :spec spec))
        (should-not sent)))))

(ert-deftest jetpacs-floor-stale-spec-strip-validation ()
  "13.5 stripping can destroy the 13.4 shape; shipping the result makes
the Companion 1201 the ENTIRE request, discarding the valid primary spec."
  (jetpacs-floor-test--with-client
      (client :granted ["surfaces.widget"]
              :profiles '(:app (:node_types ["text" "text_input" "column"]
                                :builtins [] :features [])
                          :widget (:node_types ["text" "text_input"]
                                   :builtins [] :features [])))
    (let ((sent nil))
      (jetpacs-floor-test--recording-push sent
        ;; A widget stale_spec whose body is wholly stateful loses its
        ;; REQUIRED `body' to the strip.
        (should-error
         (jetpacs-shell-push
          "widget:w1"
          :spec '(:title "T" :body (:t "text" :text "b"))
          :stale-spec '(:title "T" :body (:t "text_input" :id "ti"))))
        ;; A multi-view stale_spec whose initial view is wholly stateful
        ;; ends up naming a view that no longer exists.
        (let ((views (make-hash-table :test 'equal)))
          (puthash "list" '(:t "text_input" :id "ti") views)
          (should-error
           (jetpacs-shell-push
            "app:demo"
            :spec (jetpacs-multi-view `(("list" . ,(jetpacs-text "l"))) "list")
            :stale-spec (list :views views :initial_view "list"))))
        (should-not sent)))))

(ert-deftest jetpacs-floor-view-switched-allowlisted ()
  "SPEC 14.2/24.2: Emacs core conformance includes the generated
`view.switched' action.  Unregistered, ebp answers every tab tap
`rejected \"action not allowlisted\"' and the phone shows an error."
  (jetpacs-floor-test--with-client (client)
    (should (gethash "view.switched" (ebp-client-actions client)))
    (let (seen)
      (let ((jetpacs-shell-view-change-functions
             (list (lambda (s v) (setq seen (cons s v))))))
        (should (equal (ebp-client--handle-event-action
                        client (jetpacs-floor-test--event
                                (make-string 32 ?f)
                                :action "view.switched"
                                :args '(:view "detail")))
                       '(:status "accepted"))))
      (should (equal seen '("app:demo" . "detail")))
      (should (equal (jetpacs-shell-current-view "app:demo") "detail")))))

(ert-deftest jetpacs-floor-connect-injects-seams ()
  "`jetpacs-connect' owns the state fan-out and barrier seams and
attaches the client it dials."
  (let (got-config)
    (cl-letf (((symbol-function 'ebp-connect)
               (lambda (_host _port &rest config)
                 (setq got-config config)
                 (ebp-client-create
                  :receipt-file (make-temp-file "jetpacs-floor-conn")))))
      (unwind-protect
          (let ((client (jetpacs-connect "127.0.0.1" 8765 :token "t")))
            (should (eq client (jetpacs-client)))
            (should (eq (plist-get got-config :state-changed-function)
                        #'jetpacs--on-state-changed))
            (should (functionp
                     (plist-get got-config :before-replay-function)))
            (should (equal (plist-get got-config :token) "t")))
        (jetpacs-detach)))))

;;;; Async floor behaviors (D1 per-owner push)

(ert-deftest jetpacs-floor-async-lifecycle ()
  (jetpacs-async-reset)
  (let ((pushes nil) (starts 0))
    (cl-letf (((symbol-function 'jetpacs-shell-push)
               (lambda (&optional owner) (push owner pushes))))
      ;; First call: pending, loader once, timer armed.
      (should (equal (with-jetpacs-owner "grocy"
                       (jetpacs-async 'k (lambda (res _rej)
                                           (cl-incf starts)
                                           (funcall res 42))))
                     '(pending)))
      (should (timerp jetpacs-async--push-timer))
      ;; Flush pushes exactly the settling owner (decision D1).
      (jetpacs-async--flush-push)
      (should (equal pushes '("grocy")))
      ;; Cached read; loader not restarted.
      (should (equal (with-jetpacs-owner "grocy"
                       (jetpacs-async 'k #'ignore))
                     '(ready . 42)))
      (should (= starts 1))
      ;; Two owners settling in one tick: one flush, one push each.
      (setq pushes nil)
      (with-jetpacs-owner "a" (jetpacs-async 'ka (lambda (r _) (funcall r 1))))
      (with-jetpacs-owner "b" (jetpacs-async 'kb (lambda (r _) (funcall r 2))))
      (jetpacs-async--flush-push)
      (should (equal (sort pushes #'string<) '("a" "b")))
      ;; Reject and synchronous throw both become (error . MSG).
      (with-jetpacs-owner "a"
        (jetpacs-async 'kr (lambda (_r rej) (funcall rej "boom")))
        (should (equal (jetpacs-async 'kr #'ignore) '(error . "boom")))
        (jetpacs-async 'kt (lambda (_r _j) (error "kaboom")))
        (should (equal (jetpacs-async 'kt #'ignore) '(error . "kaboom"))))
      ;; Sweep: an unasked-for entry is dropped and its cancel runs once.
      (let ((cancelled 0))
        (with-jetpacs-owner "a"
          (jetpacs-async 'sweepme
                         (lambda (_r _j)
                           (lambda () (cl-incf cancelled)))))
        (jetpacs-async--after-push)          ; still current gen: survives
        (jetpacs-async--after-push)          ; now stale: swept
        (should-not (gethash 'sweepme jetpacs-async--cache))
        (should (= cancelled 1))
        ;; clear-owner drops only its owner's entries.
        (with-jetpacs-owner "keep"
          (jetpacs-async 'kk (lambda (_r _j) nil)))
        (with-jetpacs-owner "drop"
          (jetpacs-async 'kd (lambda (_r _j) nil)))
        (jetpacs-async-clear-owner "drop")
        (should (gethash 'kk jetpacs-async--cache))
        (should-not (gethash 'kd jetpacs-async--cache)))
      (jetpacs-async-reset)
      (should (= (hash-table-count jetpacs-async--cache) 0))
      (should-not jetpacs-async--push-timer))))


;;;; Audit commit 2: the 14.1 policy gate and the fail-closed advertisement

(ert-deftest jetpacs-floor-wake-gate-covers-every-emitter ()
  "P1-4: the offline.wake gate lives on the FLOOR, so every descriptor
emitter inherits it — not just the one that pushes documents."
  (jetpacs-floor-test--with-client (client)
    (let ((wake (jetpacs-action "a.b" :when-offline 'wake :ttl-s 60))
          (queue (jetpacs-action "a.b" :when-offline 'queue :ttl-s 60)))
      ;; Ungranted: wake refused, queue fine.
      (should-error (jetpacs-gate-descriptor-policy wake))
      (should-not (jetpacs-gate-descriptor-policy queue))
      (should-not (jetpacs-gate-descriptor-policy nil))
      ;; Granted: allowed.
      (setf (ebp-client-granted client) ["theme" "offline.wake"])
      (should-not (jetpacs-gate-descriptor-policy wake)))))

(ert-deftest jetpacs-floor-advertised-p-fails-closed-on-a-live-client ()
  "P1-5 chain: with NO client the predicates assume the richer form, but
a LIVE client missing a target's profile is a NO — SPEC 10.2 includes
that profile only when the capability was granted, so failing open would
be guaranteed wrong in exactly the gating case."
  ;; No client: open.
  (should (jetpacs-node-advertised-p "editor" :dialog))
  (should (jetpacs-builtin-advertised-p "clipboard.copy"))
  (should (jetpacs-feature-advertised-p "image.https"))
  (jetpacs-floor-test--with-client (client)
    ;; Live client, app profile present, NO dialog profile.
    (should (jetpacs-node-advertised-p "text" :app))
    (should-not (jetpacs-node-advertised-p "text" :dialog))
    (should-not (jetpacs-builtin-advertised-p "view.switch" :dialog))
    (should-not (jetpacs-feature-advertised-p "image.https" :dialog))))


;;;; Audit commit 3: SPEC 4.5 size (GATE 5) and the shared render budget

(defun jetpacs-floor-test--gate-error (thunk)
  "The error MESSAGE from THUNK, or nil.  A `should-error' alone is a
vacuous pass here: a stub client with no connection signals from the
send too, so the assertion must name WHICH gate fired."
  (condition-case err (progn (funcall thunk) nil)
    (error (error-message-string err))))

(ert-deftest jetpacs-floor-gate-size-frame-bytes ()
  "P1-3: nothing measured the spec against max_frame_bytes.  Over-frame
is worse than a 1201 — SPEC 6.2 makes it 1400 and a CLOSED connection."
  (jetpacs-floor-test--with-client
      (client :limits '(:max_frame_bytes 4096))
    (let ((msg (jetpacs-floor-test--gate-error
                (lambda ()
                  (jetpacs-shell-push
                   "app:demo" :spec (jetpacs-text (make-string 5000 ?x)))))))
      (should (string-match-p "max_frame_bytes" msg)))
    ;; A small spec clears GATE 5 and reaches the send.
    (cl-letf (((symbol-function 'ebp-client-surface-update)
               (cl-function (lambda (&rest _) 1))))
      (should (= 1 (jetpacs-shell-push "app:demo"
                                       :spec (jetpacs-text "small")))))))

(ert-deftest jetpacs-floor-gate-size-aggregates-and-depth ()
  "The four SPEC 4.5 aggregates are counted across the WHOLE spec, and
the fixed 20-level node depth is enforced — neither was measured before."
  (jetpacs-floor-test--with-client
      (client :profiles '(:app (:node_types ["text" "column" "rich_text"]
                                :builtins [] :features []))
              :limits '(:max_frame_bytes 4194304 :max_rich_spans 4))
    ;; Two rich_text nodes of 3 spans each = 6 > 4.  Each node alone is
    ;; under the cap — the AGGREGATE is the whole point.
    (let ((msg (jetpacs-floor-test--gate-error
                (lambda ()
                  (jetpacs-shell-push
                   "app:demo"
                   :spec (jetpacs-column
                          (jetpacs-rich-text (list (jetpacs-span "a")
                                                   (jetpacs-span "b")
                                                   (jetpacs-span "c")))
                          (jetpacs-rich-text (list (jetpacs-span "d")
                                                   (jetpacs-span "e")
                                                   (jetpacs-span "f")))))))))
      (should (string-match-p "max_rich_spans" msg)))
    ;; 25 nested columns blow the fixed depth cap.
    (let* ((deep (jetpacs-text "leaf"))
           (_ (dotimes (_i 25) (setq deep (jetpacs-column deep))))
           (msg (jetpacs-floor-test--gate-error
                 (lambda () (jetpacs-shell-push "app:demo" :spec deep)))))
      (should (string-match-p "max_node_depth" msg)))))

(ert-deftest jetpacs-floor-render-budget-is-idempotent ()
  "P1-2: SPEC 4.5 counts across ONE SurfaceSpec, so a nested budget wrap
must JOIN the allowance in force, not grant a fresh one — the chrome
stack puts N screens in one spec."
  (jetpacs-floor-test--with-client
      (client :limits '(:max_frame_bytes 4194304 :max_rich_spans 6))
    (jetpacs-buffer-with-budget
      (should (= (car jetpacs-buffer-budget) 6))
      (jetpacs-buffer-spend-spans (list (jetpacs-span "a")
                                        (jetpacs-span "b")
                                        (jetpacs-span "c")
                                        (jetpacs-span "d")))
      (should (= (car jetpacs-buffer-budget) 2))
      ;; The nested wrap does NOT reset to 6.
      (jetpacs-buffer-with-budget
        (should (= (car jetpacs-buffer-budget) 2))))))

(ert-deftest jetpacs-floor-cap-spans-spends-to-nothing ()
  "A spent budget yields NOTHING: the Companion rejects on a strict `>',
so one courtesy ellipsis past the cap 1201s the whole surface."
  (should (equal (jetpacs-buffer-cap-spans (list (jetpacs-span "a")) 0) nil))
  (should (= 1 (length (jetpacs-buffer-cap-spans
                        (list (jetpacs-span "a") (jetpacs-span "b")) 1))))
  (jetpacs-floor-test--with-client
      (client :limits '(:max_frame_bytes 4194304 :max_rich_spans 1))
    (jetpacs-buffer-with-budget
      (jetpacs-buffer-spend-spans (list (jetpacs-span "a")))
      (should (= (car jetpacs-buffer-budget) 0))
      ;; Budget spent: the next region emits no spans at all.
      (should (null (jetpacs-buffer-spend-spans
                     (list (jetpacs-span "b") (jetpacs-span "c"))))))))


;;;; Audit P1-6: the reserved namespace and the silent same-owner clash

(ert-deftest jetpacs-floor-claim-warns-on-same-owner-different-file ()
  "P1-6: two packages that pick the SAME owner collided in silence and
load order decided the winner.  Same-owner re-registration from the
same FILE stays silent (live coding); from a different file it is loud."
  (clrhash jetpacs--registrations)
  (clrhash jetpacs--claim-sites)
  (let ((warnings '()))
    (cl-letf (((symbol-function 'display-warning)
               (lambda (_type msg &rest _) (push msg warnings))))
      ;; Package A claims it.
      (let ((load-file-name "/pkg-a/clip.el"))
        (with-jetpacs-owner "clip" (jetpacs--claim "action" "clip.refresh")))
      (should (null warnings))
      ;; The SAME file re-evaluated: silent (the live-coding case).
      (let ((load-file-name "/pkg-a/clip.el"))
        (with-jetpacs-owner "clip" (jetpacs--claim "action" "clip.refresh")))
      (should (null warnings))
      ;; Package B, same owner, DIFFERENT file: loud.
      (let ((load-file-name "/pkg-b/clip.el"))
        (with-jetpacs-owner "clip" (jetpacs--claim "action" "clip.refresh")))
      (should (= (length warnings) 1))
      (should (string-match-p "pkg-a" (car warnings)))
      (should (string-match-p "pkg-b" (car warnings))))
    ;; Under strict namespaces it is an error, not a warning.
    (let ((jetpacs-strict-namespaces t)
          (load-file-name "/pkg-c/clip.el"))
      (should-error (with-jetpacs-owner "clip"
                      (jetpacs--claim "action" "clip.refresh")))))
  (clrhash jetpacs--registrations)
  (clrhash jetpacs--claim-sites))

(ert-deftest jetpacs-floor-base-owners-use-the-reserved-prefix ()
  "R1: base reserves `jetpacs.' and must actually USE it — an
unqualified base owner squats a name a Tier-1 author would reach for,
and D1 makes it a permanent wire identifier."
  (require 'jetpacs-clip)
  (require 'jetpacs-theme)
  (should (string-prefix-p jetpacs-reserved-owner-prefix jetpacs-clip-owner))
  ;; Every owner a base module registered carries the prefix.
  (let (base-owners)
    (maphash (lambda (key owner)
               (when (member (cdr key) '("app:jetpacs.clip" "app:jetpacs.theme"
                                         "jetpacs.clip.refresh"
                                         "jetpacs.theme.modus-toggle"))
                 (push owner base-owners)))
             jetpacs--registrations)
    (should base-owners)
    (dolist (o base-owners)
      (should (string-prefix-p jetpacs-reserved-owner-prefix o)))))


;;;; E2a: D1 — the owner reaches the handler, its continuation, and state

(ert-deftest jetpacs-floor-dispatch-binds-the-action-owner ()
  "D1 root cause: a handler runs under the owner that REGISTERED it.
Without this every owner-derived default collapses to the shell default
inside a dispatch — which is exactly where SPEC 14.4 omits the surface
context and the default is all there is."
  (jetpacs-floor-test--with-client (client)
    (let ((owner :unset) (surface :unset))
      (with-jetpacs-owner "acme.app"
        (jetpacs-defaction "acme.app.tap"
                           (lambda (_a _p)
                             (setq owner jetpacs-current-owner
                                   surface (jetpacs--default-surface))
                             'accepted)))
      (should (equal (ebp-client--handle-event-action
                      client (jetpacs-floor-test--event
                              (make-string 32 ?1) :action "acme.app.tap"
                              :surface "app:acme.app"))
                     '(:status "accepted")))
      (should (equal owner "acme.app"))
      (should (equal surface "app:acme.app"))
      (jetpacs-undefaction "acme.app.tap"))))

(ert-deftest jetpacs-floor-dispatch-owner-is-never-inherited ()
  "Unconditional, never `or'-inherited.  A re-entrant dispatch — the
dialog pump, an async loader inside a builder — would otherwise run an
OWNERLESS handler under whatever owner happened to be on the stack."
  (jetpacs-floor-test--with-client (client)
    (let ((owner :unset))
      (jetpacs-defaction "bare.tap"          ; registered with NO owner
                         (lambda (_a _p)
                           (setq owner jetpacs-current-owner)
                           'accepted))
      (with-jetpacs-owner "pumping.app"
        (jetpacs--dispatch client '(:action "bare.tap" :surface "app:demo")
                           (gethash "bare.tap" jetpacs-action-handlers)))
      (should (eq owner nil))
      (jetpacs-undefaction "bare.tap"))))

(ert-deftest jetpacs-floor-flow-continuation-keeps-the-owner ()
  "D1 must survive the timer boundary.  The dispatch binding ends with
the extent, and `jetpacs-flow-continue' is where the D2 deferred
re-push actually happens — so without the owner riding the flow the
work lands on the shell default.  Driven from a SURFACELESS event (SPEC
14.4 reminder/trigger/shortcut/pie), where there is no `:surface' to
fall back on either."
  (jetpacs-floor-test--with-client (client)
    (let ((in-handler :unset) (in-continuation :unset))
      (with-jetpacs-owner "org.agenda"
        (jetpacs-defaction "org.agenda.open"
                           (lambda (_a _p)
                             (setq in-handler jetpacs-current-owner)
                             (jetpacs-flow-continue
                              (lambda ()
                                (setq in-continuation
                                      (jetpacs--default-surface))))
                             'accepted)))
      (jetpacs--dispatch client '(:action "org.agenda.open")
                         (gethash "org.agenda.open" jetpacs-action-handlers))
      (should (equal in-handler "org.agenda"))
      (cl-loop repeat 20 until (not (eq in-continuation :unset))
               do (accept-process-output nil 0.02))
      (should (equal in-continuation "app:org.agenda"))
      (jetpacs-undefaction "org.agenda.open"))))

(ert-deftest jetpacs-floor-build-does-not-inherit-across-a-dispatch ()
  "The containment the dispatch binding makes necessary: an OWNERLESS
root's builder must NOT run under the handler's owner, or a zero-arg
push or `jetpacs-ui-state' inside it silently reads and writes another
surface's SPEC 14.6 input store."
  (jetpacs-floor-test--with-client (client)
    (let ((build-owner :unset))
      (jetpacs-shell-define-root "app:main"     ; no with-jetpacs-owner
                                 (lambda ()
                                   (setq build-owner jetpacs-current-owner)
                                   (jetpacs-text "hi")))
      (with-jetpacs-owner "acme"
        (jetpacs-defaction "acme.tap"
                           (lambda (_a _p)
                             (jetpacs-shell--build
                              "app:main"
                              (alist-get "app:main" jetpacs-shell--roots
                                         nil nil #'equal))
                             'accepted)))
      (jetpacs--dispatch client '(:action "acme.tap" :surface "app:acme")
                         (gethash "acme.tap" jetpacs-action-handlers))
      (should (eq build-owner nil))
      (jetpacs-undefaction "acme.tap"))))

(ert-deftest jetpacs-floor-state-change-binds-the-surface-owner ()
  "The OTHER device-event entry point, in the same jsonrpc extent.
Without this an app gets its owner on a tap and loses it on a text
edit — worse than a uniform nil, because a handler written against the
repaired action path would silently misroute here."
  (jetpacs-floor-test--with-client (client)
    (let ((owner :unset))
      (with-jetpacs-owner "d1app"
        (jetpacs-shell-define-root "app:d1app" (lambda () (jetpacs-text "x")))
        (jetpacs-on-state-change "field"
                                 (lambda (_v) (setq owner jetpacs-current-owner))
                                 "app:d1app"))
      (jetpacs--on-state-changed client "app:d1app" 1 "field" "typed")
      (should (equal owner "d1app")))))


;;;; E2b: the D1 surface-context gate

(ert-deftest jetpacs-floor-owned-action-rejects-a-foreign-surface ()
  "SPEC 14.4: the surface context is validated BEFORE behavior.  An
owned action tapped from a surface its owner does not hold is rejected
with the handler NEVER invoked — pre-fix a nonconforming peer could run
any owner's root builder from any other owner's action."
  (jetpacs-floor-test--with-client (client)
    (let ((runs 0))
      (with-jetpacs-owner "acme"
        (jetpacs-defaction "acme.tap"
                           (lambda (_a _p) (cl-incf runs) 'accepted)))
      (let ((warning-minimum-log-level :emergency))
        (should (eq (jetpacs--dispatch
                     client '(:action "acme.tap" :surface "app:other")
                     (gethash "acme.tap" jetpacs-action-handlers))
                    'rejected)))
      (should (= runs 0))
      ;; The owner's own surface passes…
      (should (eq (jetpacs--dispatch
                   client '(:action "acme.tap" :surface "app:acme")
                   (gethash "acme.tap" jetpacs-action-handlers))
                  'accepted))
      ;; …and so does a SURFACELESS SPEC 14.4 event (reminder/trigger).
      (should (eq (jetpacs--dispatch
                   client '(:action "acme.tap")
                   (gethash "acme.tap" jetpacs-action-handlers))
                  'accepted))
      (should (= runs 2))
      (jetpacs-undefaction "acme.tap"))))

(ert-deftest jetpacs-floor-owned-secondary-surface-passes-the-gate ()
  "The scope is the owner's SURFACES, plural: a secondary surface
claimed under the owner is as much theirs as the D1 primary."
  (jetpacs-floor-test--with-client (client)
    (let ((runs 0))
      (with-jetpacs-owner "acme"
        (jetpacs--claim "surface" "app:acme-detail")
        (jetpacs-defaction "acme.tap"
                           (lambda (_a _p) (cl-incf runs) 'accepted)))
      (should (eq (jetpacs--dispatch
                   client '(:action "acme.tap" :surface "app:acme-detail")
                   (gethash "acme.tap" jetpacs-action-handlers))
                  'accepted))
      (should (= runs 1))
      (jetpacs--unclaim "surface" "app:acme-detail")
      (jetpacs-undefaction "acme.tap"))))

(ert-deftest jetpacs-floor-global-verb-passes-from-any-surface ()
  "An owned action registered :any-surface is a GLOBAL VERB: base's
theme toggle owns ZERO surfaces and any surface may render its button —
a real tap always carries that surface, so without the exemption the
gate would reject every one."
  (jetpacs-floor-test--with-client (client)
    (let ((runs 0))
      (with-jetpacs-owner "acme"
        (jetpacs-defaction "acme.global"
                           (lambda (_a _p) (cl-incf runs) 'accepted)
                           :any-surface t))
      (should (eq (jetpacs--dispatch
                   client '(:action "acme.global" :surface "app:anything")
                   (gethash "acme.global" jetpacs-action-handlers))
                  'accepted))
      (should (= runs 1))
      ;; Re-registration WITHOUT the flag rescopes it.
      (with-jetpacs-owner "acme"
        (jetpacs-defaction "acme.global" (lambda (_a _p) 'accepted)))
      (let ((warning-minimum-log-level :emergency))
        (should (eq (jetpacs--dispatch
                     client '(:action "acme.global" :surface "app:anything")
                     (gethash "acme.global" jetpacs-action-handlers))
                    'rejected)))
      (jetpacs-undefaction "acme.global"))))


;;;; E2c: the action's introspection schema (:args / :doc)

(ert-deftest jetpacs-floor-action-schema-round-trips ()
  "A typed registration reads back through the accessor, verbatim.
poc-v1's arg schemas are what an action editor, a completion source or
a builder UI reads to know an action has a `value' it must supply; the
registry lost them in the rebuild and this is the round trip that says
they are back."
  (jetpacs-floor-test--with-client (_client)
    (with-jetpacs-owner "journal"
      (jetpacs-defaction "journal.capture" (lambda (_a _p) 'accepted)
                         :args '((:name value :type "text" :required t)
                                 (:name date :type "date"))
                         :doc "Append text to the current journal day."))
    (should (equal (jetpacs-action-schema "journal.capture")
                   '(:args ((:name value :type "text" :required t)
                            (:name date :type "date"))
                     :doc "Append text to the current journal day."
                     :any-surface nil)))
    ;; A global verb reports the flag alongside its schema.
    (with-jetpacs-owner "journal"
      (jetpacs-defaction "journal.toggle" (lambda (_a _p) 'accepted)
                         :any-surface t :doc "Flip the journal view."))
    (should (equal (jetpacs-action-schema "journal.toggle")
                   '(:args nil :doc "Flip the journal view." :any-surface t)))
    ;; An unregistered name is nil — distinguishable from a registered
    ;; action that simply declared nothing.
    (should-not (jetpacs-action-schema "journal.nothing-here"))
    (jetpacs-undefaction "journal.capture")
    (jetpacs-undefaction "journal.toggle")))

(ert-deftest jetpacs-floor-action-schema-rejects-malformed-args ()
  "The schema is validated at REGISTRATION, loudly, and atomically.
A malformed schema is a code bug in the app; deferred to the first
editor that reads it, it would surface months later and nowhere near
the defaction that wrote it.  The name must stay UNREGISTERED after a
refusal — a half-registered action is worse than none."
  (jetpacs-floor-test--with-client (_client)
    (dolist (bad '("not a list"
                   ((:name "value"))          ; :name is not a symbol
                   ((:type "text"))           ; no :name at all
                   ((:name))                  ; not even a plist
                   ((:name value :type date)) ; :type is not a string
                   ((:name value :required "yes")))) ; not a boolean
      (should-error (jetpacs-defaction "acme.bad" (lambda (_a _p) 'accepted)
                                       :args bad))
      (should-not (gethash "acme.bad" jetpacs-action-handlers)))
    ;; DOC is a string when present.
    (should-error (jetpacs-defaction "acme.bad" (lambda (_a _p) 'accepted)
                                     :doc 7))
    (should-not (gethash "acme.bad" jetpacs-action-handlers))
    ;; The type VOCABULARY is open on purpose: an app-defined string
    ;; passes, because the thing that reads a type is the app's editor.
    (jetpacs-defaction "acme.ok" (lambda (_a _p) 'accepted)
                       :args '((:name recipe :type "grocy-recipe-ref")))
    (should (equal (plist-get (jetpacs-action-schema "acme.ok") :args)
                   '((:name recipe :type "grocy-recipe-ref"))))
    (jetpacs-undefaction "acme.ok")))

(ert-deftest jetpacs-floor-action-schema-survives-the-attach-replay ()
  "The schema outlives the session, like the staging table it rides
beside.  Registrations are load-time forms replayed into every new
client; metadata that evaporated on a reconnect would leave the
introspection answering differently before and after a dropped socket.
Nothing about it reaches the wire — the replay is the ALLOWLIST."
  (jetpacs-floor-test--with-client (_client)
    (with-jetpacs-owner "journal"
      (jetpacs-defaction "journal.capture" (lambda (_a _p) 'accepted)
                         :args '((:name value :type "text" :required t))
                         :doc "Append text."))
    (jetpacs-detach)
    (let ((next (jetpacs-floor-test--client)))
      (jetpacs-attach next)
      (should (gethash "journal.capture" (ebp-client-actions next)))
      (should (equal (jetpacs-action-schema "journal.capture")
                     '(:args ((:name value :type "text" :required t))
                       :doc "Append text." :any-surface nil))))
    (jetpacs-undefaction "journal.capture")))

(ert-deftest jetpacs-floor-schemaless-registration-still-dispatches ()
  "Back-compat: metadata never gates anything.  Every action in the
tree predates the schema and declares none — they register, dispatch
and report an EMPTY schema rather than nil, which is how a caller
tells them from a name nobody registered.  And a re-registration that
omits the schema CLEARS the stale one, the rule `:any-surface' already
follows."
  (jetpacs-floor-test--with-client (client)
    (let ((runs 0))
      (jetpacs-defaction "plain.tap" (lambda (_a _p) (cl-incf runs) 'accepted))
      (should (equal (jetpacs-action-schema "plain.tap")
                     '(:args nil :doc nil :any-surface nil)))
      (should (eq (jetpacs--dispatch client '(:action "plain.tap")
                                     (gethash "plain.tap"
                                              jetpacs-action-handlers))
                  'accepted))
      (should (= runs 1))
      ;; Schema on, then off again.
      (jetpacs-defaction "plain.tap" (lambda (_a _p) 'accepted)
                         :doc "Now documented.")
      (should (equal (plist-get (jetpacs-action-schema "plain.tap") :doc)
                     "Now documented."))
      (jetpacs-defaction "plain.tap" (lambda (_a _p) 'accepted))
      (should-not (plist-get (jetpacs-action-schema "plain.tap") :doc))
      (jetpacs-undefaction "plain.tap")
      (should-not (jetpacs-action-schema "plain.tap")))))


;;;; E2e: hook isolation and the per-surface snackbar

(ert-deftest jetpacs-floor-after-push-hook-is-isolated ()
  "The push hooks run with the effect ALREADY COMMITTED — the frame is
on the wire — so a subscriber's signal escaping into the dispatch would
answer a permanent SPEC 14.4 rejected for a push that happened.  One
broken subscriber logs its SYMBOL; the rest still run; the reply stands."
  (jetpacs-floor-test--with-client (client)
    (let ((later nil) (sent nil) (status nil)
          (jetpacs-shell-after-push-hook jetpacs-shell-after-push-hook))
      (add-hook 'jetpacs-shell-after-push-hook
                (lambda () (error "subscriber exploded")))
      (add-hook 'jetpacs-shell-after-push-hook
                (lambda () (setq later t)) t)
      (with-jetpacs-owner "demo"
        (jetpacs-shell-define-root "demo" (lambda () (jetpacs-text "x")))
        (jetpacs-defaction "demo.push"
                           (lambda (_a _p)
                             (jetpacs-shell-push "app:demo")
                             'accepted)))
      (cl-letf (((symbol-function 'ebp-client-surface-update)
                 (cl-function (lambda (_c surface &rest _)
                                (push surface sent) 7))))
        (setq status (jetpacs--dispatch
                      client '(:action "demo.push" :surface "app:demo")
                      (gethash "demo.push" jetpacs-action-handlers))))
      (should (eq status 'accepted))
      (should later)
      (should (equal sent '("app:demo")))
      (jetpacs-undefaction "demo.push"))))

(ert-deftest jetpacs-floor-view-switched-subscribers-are-isolated ()
  "A view switch ALREADY HAPPENED on the device when the subscribers
run; one Tier-1 subscriber's signal must not delete the durable record
for it."
  (jetpacs-floor-test--with-client (client)
    (let ((later nil) (status nil)
          (jetpacs-shell-view-change-functions
           jetpacs-shell-view-change-functions))
      (add-hook 'jetpacs-shell-view-change-functions
                (lambda (_s _v) (error "subscriber exploded")))
      (add-hook 'jetpacs-shell-view-change-functions
                (lambda (_s _v) (setq later t)) t)
      (setq status (jetpacs--dispatch
                    client '(:action "view.switched"
                             :args (:view "hub") :surface "app:demo")
                    (gethash "view.switched" jetpacs-action-handlers)))
      (should (eq status 'accepted))
      (should later))))

(ert-deftest jetpacs-floor-snackbar-does-not-cross-owners ()
  "D1: owner A's queued confirmation must never drain into owner B's
push — the one-slot global did exactly that."
  (jetpacs-floor-test--with-client
      (client :profiles '(:app (:node_types ["text" "scaffold" "column"]
                                :builtins [] :features [])))
    (let ((sent nil))
      (with-jetpacs-owner "aa"
        (jetpacs-shell-define-root
         "aa" (lambda () '(:t "scaffold" :body (:t "text" :text "a")))))
      (with-jetpacs-owner "bb"
        (jetpacs-shell-define-root
         "bb" (lambda () '(:t "scaffold" :body (:t "text" :text "b")))))
      (jetpacs-shell-notify "a-saved" "aa")
      (cl-letf (((symbol-function 'ebp-client-surface-update)
                 (cl-function (lambda (_c surface spec &rest _)
                                (push (cons surface
                                            (plist-get spec :snackbar))
                                      sent)
                                7))))
        ;; B's push carries NO snackbar; A's still does.
        (jetpacs-shell-push "app:bb")
        (jetpacs-shell-push "app:aa")
        (should (equal sent '(("app:aa" . "a-saved")
                              ("app:bb" . nil))))))))


;;;; E3: W10 / refusal hygiene

(ert-deftest jetpacs-floor-refused-push-keeps-snackbar-skips-hook ()
  "A refusal concluded synchronously inside the send: the frame never
left, so the user's queued feedback is REQUEUED for the B8 retry — the
audit reproduced it being destroyed — and the after-push hook (whose
contract is a successful send) does not run."
  (jetpacs-floor-test--with-client
      (client :profiles '(:app (:node_types ["text" "scaffold" "column"]
                                :builtins [] :features [])))
    (let ((hook-ran nil)
          (jetpacs-shell-after-push-hook jetpacs-shell-after-push-hook))
      (add-hook 'jetpacs-shell-after-push-hook (lambda () (setq hook-ran t)))
      (with-jetpacs-owner "grocy"
        (jetpacs-shell-define-root
         "grocy" (lambda () '(:t "scaffold" :body (:t "text" :text "r")))))
      (jetpacs-shell-notify "saved" "grocy")
      (setf (ebp-client-outstanding client) ebp-overload-hold)
      (jetpacs-shell-push "app:grocy")
      (should (equal (gethash "app:grocy" jetpacs-shell--snackbars) "saved"))
      (should-not hook-ran)
      ;; And the count advanced for the backoff.
      (should (= 1 (gethash "app:grocy" jetpacs-shell--refusal-counts))))))

(ert-deftest jetpacs-floor-refusal-backoff-caps ()
  "The B8 retry is counted and CAPPED: pre-fix the loop was unbounded
and backoff-free against a session whose ceiling stayed held."
  (jetpacs-floor-test--with-client (client)
    (let ((scheduled 0) (timers 0))
      (cl-letf (((symbol-function 'jetpacs-shell--schedule-repush)
                 (lambda (_s) (cl-incf scheduled)))
                ((symbol-function 'run-at-time)
                 (lambda (&rest _) (cl-incf timers) nil)))
        ;; First refusal: the normal debounce.
        (jetpacs-shell--note-refusal "app:x")
        (should (= scheduled 1))
        ;; Later ones: deferred with growing delay.
        (jetpacs-shell--note-refusal "app:x")
        (should (= timers 1))
        ;; Past the cap: nothing scheduled at all.
        (puthash "app:x" jetpacs-shell-refusal-max-retries
                 jetpacs-shell--refusal-counts)
        (let ((s scheduled) (tm timers))
          (jetpacs-shell--note-refusal "app:x")
          (should (= scheduled s))
          (should (= timers tm)))))))

(ert-deftest jetpacs-floor-send-remove-drops-permanent-errors ()
  "A -32601/1201 answer to surface.remove will only re-fail: requeueing
it re-sends at every 10.3 barrier forever.  Transient errors requeue."
  (jetpacs-floor-test--with-client (client)
    (setq jetpacs-shell--pending-removals nil)
    (cl-letf (((symbol-function 'ebp-client-surface-remove)
               (cl-function (lambda (_c _s &key callback)
                              (funcall callback nil '(:code -32601))
                              1))))
      (jetpacs-shell--send-remove "app:gone"))
    (should-not (member "app:gone" jetpacs-shell--pending-removals))
    (cl-letf (((symbol-function 'ebp-client-surface-remove)
               (cl-function (lambda (_c _s &key callback)
                              (funcall callback nil '(:code -32603))
                              1))))
      (jetpacs-shell--send-remove "app:flaky"))
    (should (member "app:flaky" jetpacs-shell--pending-removals))
    (setq jetpacs-shell--pending-removals nil)))

(provide 'jetpacs-floor-test)
;;; jetpacs-floor-test.el ends here
