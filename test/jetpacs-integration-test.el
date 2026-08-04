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
;; Order matters and is the point: chrome's `with-eval-after-load' fires
;; when navigate arrives.  Requiring chrome FIRST exercises the backfill
;; branch, which is the one no other suite reaches.
(require 'jetpacs-chrome)
(require 'jetpacs-navigate)

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

(provide 'jetpacs-integration-test)
;;; jetpacs-integration-test.el ends here
