;;; jetpacs-integration-test.el --- cross-module seam wiring -*- lexical-binding: t; -*-

;;; Commentary:

;; The suite that loads the application layer TOGETHER.
;;
;; Every other elisp suite runs in its own batch Emacs with a minimal
;; `require' set, which is what keeps them fast and independent — and is
;; also, per AUDIT-ja1-ja2 section 3(h), the structural reason the harness
;; is blind to a whole class of defect: a seam that only exists when two
;; modules are both loaded is tested by NO process.  The drill seam is the
;; live example.  `jetpacs-chrome' publishes itself as the navigator's
;; drill host from a `with-eval-after-load', and every navigate test binds
;; `jetpacs-navigate-drill-function' to a stub — so the entire drill
;; feature can be deleted and CI stays green.
;;
;; This file's rule: require the real modules, stub nothing that the seam
;; runs through, and assert the wiring that only exists between them.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-device)
;; The org ADAPTER, for the reset registration it carries: `ebp-org.el'
;; may not name a floor symbol, so its reset reaches
;; `jetpacs-reset-functions' through this shim or not at all — and only
;; a process that has both the floor and the shim can see that.
(require 'jetpacs-org)
;; Order matters and is the point: chrome's `with-eval-after-load' fires
;; when navigate arrives.  Requiring chrome FIRST exercises the backfill
;; branch, which is the one no other suite reaches.
(require 'jetpacs-chrome)
(require 'jetpacs-navigate)
;; Required LAST on purpose: theme subscribes to `jetpacs-ready-functions'
;; at depth -50 after the shell (90) and chrome (default) are already on
;; it, so the ordering assertions below exercise the late-loader case —
;; `add-hook' re-sorts by depth on every add, in either load order.
(require 'jetpacs-theme)

;;;; The drill seam (T1)

(ert-deftest jetpacs-integration-drill-seam-is-wired ()
  "`jetpacs-chrome' publishes itself as the global drill host once
`jetpacs-navigate' is loaded.  Deleting chrome's `with-eval-after-load'
must fail HERE — no other suite loads both modules, and every navigate
test binds the seam to a stub."
  (should (eq jetpacs-navigate-drill-function #'jetpacs-chrome--drill)))

(ert-deftest jetpacs-integration-drill-refuses-a-stackless-surface ()
  "The seam contract says the host NEVER signals.  A surface with no
chrome stack — torn down, or never chrome's — is refused with nil so the
navigator runs its documented degrade instead of answering `rejected'
for an effect that did not happen."
  (let ((jetpacs-chrome--stacks (make-hash-table :test #'equal)))
    (should-not
     (let ((inhibit-message t))
       (jetpacs-chrome--drill "app:never-chromes" (lambda (_back) nil) "L")))))

;;;; The device teardown hook (T6)

(ert-deftest jetpacs-integration-device-teardown-hook-is-wired ()
  "`jetpacs-device' adds its sweep to `jetpacs-teardown-functions' at
load.  Deleting that `add-hook' is green across every existing suite —
they reach the sweep through `jetpacs-test-reset-state' instead, which
calls it directly and so cannot see the hook go missing."
  (should (memq #'jetpacs-device--on-teardown jetpacs-teardown-functions)))

(ert-deftest jetpacs-integration-device-teardown-sweeps-through-the-hook ()
  "Driving the PUBLIC teardown verb (not the reset helper) must sweep the
device's local reminder bookkeeping for that owner and no other."
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jetpacs-integration-receipts"))))
    (setf (ebp-client-state client) 'ready
          (ebp-client-granted client) ["reminders.owner"])
    (cl-letf (((symbol-function 'ebp-client--request)
               (lambda (_c _m _p callback &optional _t)
                 ;; Confirm immediately: we are testing teardown, not the
                 ;; in-flight generation guard.
                 (funcall callback '(:accepted 1) nil)
                 42)))
      (unwind-protect
          (progn
            (jetpacs-attach client)
            (jetpacs-reminders-set '((:id "r" :title "T" :at_ms 1)) :owner "keep")
            (jetpacs-reminders-set '((:id "r" :title "T" :at_ms 1)) :owner "sweep")
            (should (jetpacs-reminders "keep"))
            (should (jetpacs-reminders "sweep"))
            ;; The public verb, which runs jetpacs-teardown-functions.
            (let ((inhibit-message t)) (jetpacs-teardown-owner "sweep"))
            (should-not (jetpacs-reminders "sweep"))
            ;; ...and only that owner.
            (should (jetpacs-reminders "keep")))
        (jetpacs-detach)
        (jetpacs-test-reset-state)))))

;;;; The W10 sender ceiling, stub-free (T5)

(ert-deftest jetpacs-integration-w10-ceiling-is-real-not-stubbed ()
  "SPEC 22.3: the sender ceiling refuses LOCALLY at `ebp-overload-hold'
outstanding requests, concluding the callback synchronously and exactly
once with a `:ebp-local'-tagged 1401.

The device suite's version of this stubs `ebp-client--request' wholesale
and hands the callback a hand-written 1401 — it asserts that
`jetpacs-reminders-set' READS a refusal, never that ebp PRODUCES one.
Here the real `ebp-client--request' runs; only the transport is stopped,
so outstanding accumulates for real and the ceiling does its own work."
  (let ((refusals 0) (local-tags 0))
    (ebp-test--with-companion
        (server client
         ;; A conformant companion that completes the handshake, grants
         ;; reminders.owner, and then simply never answers reminders.set —
         ;; so outstanding accumulates for real, over a real socket.
         (ebp-test--kat-script
          :welcome-fn (lambda (w)
                        (plist-put w :granted ["theme" "reminders.owner"])))
         :wants '("theme" "reminders.owner"))
      (should (ebp-test--wait
               (lambda () (eq (ebp-client-state client) 'ready))))
      (unwind-protect
          (let ((ebp-overload-hold 3)
                (ebp-overload-resume 1))
            (jetpacs-attach client)
            ;; Fill the ceiling with real, unconcluded wire requests.
            (dotimes (i 3)
              (jetpacs-reminders-set
               (list (list :id (format "r%d" i) :title "T" :at_ms 1))
               :owner (format "o%d" i)))
            (should (= 3 (ebp-client-outstanding client)))
            ;; Let the three filling requests LAND before snapshotting, or
            ;; the comparison below counts them instead of the refused one.
            (dotimes (_ 5) (accept-process-output nil 0.02))
            (let ((sent-before (length (funcall (plist-get server :received)))))
              (jetpacs-reminders-set
               '((:id "over" :title "T" :at_ms 1)) :owner "over"
               :callback (lambda (_c err)
                           (when (eql (plist-get err :code) 1401)
                             (setq refusals (1+ refusals)))
                           (when (plist-get err :ebp-local)
                             (setq local-tags (1+ local-tags)))))
              ;; Concluded synchronously and exactly once...
              (should (= refusals 1))
              ;; ...tagged as OURS, which is what distinguishes it from a
              ;; peer's byte-identical mandatory 1401 (E3's discriminator)...
              (should (= local-tags 1))
              ;; ...and it never reached the wire.  Pump first, so this
              ;; cannot pass merely because the frame is still in flight.
              (dotimes (_ 5) (accept-process-output nil 0.02))
              (should (= sent-before
                         (length (funcall (plist-get server :received))))))
            ;; The latch is sticky: still refused at 3 outstanding.
            (setq refusals 0)
            (jetpacs-reminders-set
             '((:id "again" :title "T" :at_ms 1)) :owner "again"
             :callback (lambda (_c err)
                         (when (eql (plist-get err :code) 1401)
                           (setq refusals (1+ refusals)))))
            (should (= refusals 1))
            (should (ebp-client-outstanding-held client)))
        (jetpacs-detach)
        (jetpacs-test-reset-state)))))


;;;; The notify raise (SPEC 18.2.1) — shell x ebp seam

(ert-deftest jetpacs-integration-notify-raise-carries-the-action ()
  "`jetpacs-shell-notify' hands :action-label/:duration through to the
raise and dispatches :on-action exactly when the reply says the user
tapped the button — dismissed and errored raises run nothing."
  (let (sent fired)
    (cl-letf (((symbol-function 'jetpacs-connected-p) (lambda () t))
              ((symbol-function 'jetpacs-granted-p) (lambda (_cap) t))
              ((symbol-function 'jetpacs-client) (lambda () 'client))
              ((symbol-function 'ebp-client-snackbar-show)
               (cl-function
                (lambda (_client message &key action-label duration callback)
                  (setq sent (list message action-label duration callback))))))
      (jetpacs-shell-notify "saved" nil
                            :action-label "Undo"
                            :on-action (lambda () (setq fired t)))
      (should (equal (nth 0 sent) "saved"))
      (should (equal (nth 1 sent) "Undo"))
      (should-not (nth 2 sent))
      (funcall (nth 3 sent) "dismissed" nil)
      (should-not fired)
      (funcall (nth 3 sent) "action" nil)
      (should fired))))

(ert-deftest jetpacs-integration-notify-queue-drops-the-action ()
  "Ungranted, notify queues TEXT alone: the action is dropped with its
timing rather than queued to fire stale on some later push."
  (cl-letf (((symbol-function 'jetpacs-connected-p) (lambda () nil)))
    (with-jetpacs-owner "notifydemo"
      (jetpacs-shell-notify "saved" "notifydemo"
                            :action-label "Undo"
                            :on-action #'ignore))
    (unwind-protect
        (should (equal (gethash "app:notifydemo" jetpacs-shell--snackbars)
                       "saved"))
      (remhash "app:notifydemo" jetpacs-shell--snackbars))))

;;;; The READY ladder (A-2) and its sibling (A-3)

;; The ladder the floor used to spell as an fboundp chain is now
;; `jetpacs-ready-functions', and every module subscribes at LOAD.  That
;; makes membership and ORDER properties of the loaded set — which only
;; this suite has, because it is the only process that loads the
;; application layer together.  Every other suite sees whichever one
;; module it required and would stay green with the rest deleted.

(defun jetpacs-integration-test--client ()
  "A bare client struct for driving the floor's hooks by hand."
  (ebp-client-create
   :receipt-file (make-temp-file "jetpacs-integration-receipts")))

(defun jetpacs-integration-test--exploding-ready-member (_client)
  "A `jetpacs-ready-functions' member that always signals."
  (error "integration probe: the ready member exploded"))

(ert-deftest jetpacs-integration-ready-hook-carries-every-loaded-module ()
  "Each loaded module puts its own READY work on the hook.
The floor no longer names a single module, so a deleted `add-hook' is
green in the module's OWN suite (nothing there drains the hook) and
green everywhere else (nothing there loads the module).  This is where
it fails."
  (should (memq #'jetpacs-shell--on-ready jetpacs-ready-functions))
  (should (memq #'jetpacs-theme--on-ready jetpacs-ready-functions))
  (should (memq #'jetpacs-chrome--on-ready jetpacs-ready-functions)))

(ert-deftest jetpacs-integration-ready-hook-orders-theme-before-shell ()
  "The palette frame is pinned AHEAD of the content drain, statically.
Theme sits at depth -50 and the shell drain at 90, so a screen drained
at READY paints in the palette this session already sent — the 0.2 s
wrong-palette flash the depths exist to kill.  Asserted on the GLOBAL
value: the depth lives there, and a let-bound literal would discard it
and pass on list order alone."
  (let ((theme (cl-position #'jetpacs-theme--on-ready jetpacs-ready-functions))
        (shell (cl-position #'jetpacs-shell--on-ready jetpacs-ready-functions)))
    (should theme)
    (should shell)
    (should (< theme shell))))

(ert-deftest jetpacs-integration-ready-hook-runs-theme-before-shell ()
  "The dynamic half: the drain CALLS them in that order.
`add-hook' stores symbols, so `run-hook-wrapped' inside
`jetpacs-run-isolated' funcalls them through their `symbol-function' —
which is what lets a `cl-letf' log the real dispatch rather than
re-reading the same list the static test already read."
  (let ((log '())
        ;; chrome's member runs for real between the two; keep its memo
        ;; out of the global.
        (jetpacs-chrome--window-classes nil)
        (client (jetpacs-integration-test--client)))
    (cl-letf (((symbol-function 'jetpacs-theme--on-ready)
               (lambda (_client) (push 'theme log)))
              ((symbol-function 'jetpacs-shell--on-ready)
               (lambda (_client) (push 'shell log))))
      (jetpacs--on-client-ready client))
    (should (equal (nreverse log) '(theme shell)))))

(ert-deftest jetpacs-integration-ready-hook-isolates-a-failing-member ()
  "One member's signal must not cost the session everything after it.
Pinned at depth -100 so the probe runs FIRST: without the isolation in
`jetpacs-run-isolated' the whole ladder — palette, chrome seed, and the
shell's drain of the pushes SYNCING refused — dies on the first
subscriber that breaks."
  (let ((pushed '())
        (drained nil)
        ;; No client is attached, so the palette send is a no-op anyway;
        ;; pinning the mode keeps it one whatever ran before this test.
        (jetpacs-theme-mode 'off)
        (jetpacs-chrome--window-classes nil)
        (jetpacs-shell--repush-pending '("app:integrationdrain"))
        (client (jetpacs-integration-test--client)))
    (add-hook 'jetpacs-ready-functions
              #'jetpacs-integration-test--exploding-ready-member -100)
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-shell-push)
                   (lambda (surface &rest _) (push surface pushed) 1)))
          ;; Escaping here IS the failure — no `should-error' wrapper.
          (let ((inhibit-message t))
            (jetpacs--on-client-ready client))
          (setq drained (null jetpacs-shell--repush-pending)))
      (remove-hook 'jetpacs-ready-functions
                   #'jetpacs-integration-test--exploding-ready-member))
    ;; The drain ran, past the member that blew up ahead of it.
    (should drained)
    (should (equal pushed '("app:integrationdrain")))))

(ert-deftest jetpacs-integration-connect-installs-the-ready-bridge ()
  "`jetpacs-connect' hands ebp the NAMED bridge, and only one of it.
Named rather than a closure so this `memq' is possible at all — the
audit deleted the old inline install with every suite green.
`cl-pushnew' is the other half: a reconnect that re-installs on the
same client must not drain the ladder twice."
  (let ((client (jetpacs-integration-test--client)))
    (should-not (ebp-client-ready-functions client))
    (jetpacs--install-ready-hooks client)
    (should (memq #'jetpacs--on-client-ready
                  (ebp-client-ready-functions client)))
    (jetpacs--install-ready-hooks client)
    (should (= 1 (cl-count #'jetpacs--on-client-ready
                           (ebp-client-ready-functions client))))))

(ert-deftest jetpacs-integration-before-replay-hook-is-wired ()
  "The shell's SPEC 10.3 step-3 push rides the floor's sibling ladder.
The floor used to reach for `jetpacs-shell--before-replay' by name; now
the shell subscribes, and nothing but this suite would notice the
`add-hook' go missing."
  (should (memq #'jetpacs-shell--before-replay
                jetpacs-before-replay-functions)))

;;;; The reset ladder — the fourth and last

(ert-deftest jetpacs-integration-reset-hook-carries-every-loaded-module ()
  "Each loaded module puts its own reset on `jetpacs-reset-functions'.
The floor used to spell this as an fboundp ladder that named seven
module resets, so a rename on either side just stopped resets running.
Membership is the replacement, and it is only a property of a process
that loads more than one of them: a module's own suite never drains the
hook, and every other suite lacks the module.

`ebp-org-reset' is the one that proves the tier rule.  The engine may
not name a `jetpacs-' symbol — the delineation guard loads
`emacs/ebp-org.el' alone and fails on the first one — so the
registration belongs to the jetpacs-side shim `jetpacs-org.el', and
this is the assertion that the shim actually made it."
  (should (memq #'jetpacs-async-reset jetpacs-reset-functions))
  (should (memq #'jetpacs-device-reset jetpacs-reset-functions))
  (should (memq #'ebp-org-reset jetpacs-reset-functions)))

(provide 'jetpacs-integration-test)
;;; jetpacs-integration-test.el ends here
