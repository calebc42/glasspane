;;; smoke-a8-coldstart.el --- A8 P1 gate: replay staleness after process death -*- lexical-binding: t; -*-

;; The device half of d11300e (docs/RESEARCH-A8-2026-07-25.md section 5.2):
;; `jetpacs--applied-revisions' must seed from the welcome floors at the
;; SPEC 10.3 step-3 barrier, so an event replayed after a cold start is
;; gated against the floors the Companion actually holds — not against an
;; empty table that answers "not stale" for everything.
;;
;; Two phases, selected by EBP_PHASE:
;;
;;   phase1 — connect through the production `jetpacs-connect', push
;;            app:a8smoke at some floor F1 (a button whose action queues
;;            offline), print A8_FLOOR=F1, and DIE without ceremony: the
;;            in-memory applied table dies with the process.
;;            Then (adb, outside this script) tap the button while
;;            disconnected: the Companion durably queues the event with
;;            revision_seen F1.
;;
;;   phase2 — a FRESH process (empty tables, same receipt file = a real
;;            restart).  The root is :required this time, so the barrier
;;            order is exactly the research scenario: seed adopts F1 from
;;            the live welcome, the step-3 push claims F1+1, queue.replay
;;            delivers the tap with revision_seen F1 -> the opted-in
;;            handler MUST see stale.  Then a second tap against the
;;            fresh snapshot MUST dispatch accepted (the healthy path).
;;
;; The fix-discriminating assertion is the FIRST one: the seed snapshot
;; is taken inside the barrier, after `jetpacs--before-replay' and before
;; anything else runs — pre-d11300e the table at that instant was EMPTY.
;; (The stale verdict alone would pass pre-fix too in this choreography,
;; because the required push's `applied' confirmation lands before the
;; replayed event; the ERT pair in jetpacs-floor-test.el is the unit
;; discriminator.)
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)

(defconst smoke-a8--phase (or (getenv "EBP_PHASE") "phase1"))
(defconst smoke-a8--expect-floor
  (let ((s (getenv "EBP_EXPECT_FLOOR"))) (and s (string-to-number s))))
(defconst smoke-a8--receipts
  (expand-file-name "a8-coldstart-receipts" temporary-file-directory))

(defvar smoke-a8--fails 0)
(defun smoke-a8--check (label ok &optional detail)
  (princ (format "%-52s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-a8--fails (1+ smoke-a8--fails))))

(defvar smoke-a8--dispatches nil
  "Each handler run: (REV-SEEN STALE-P STATUS), newest first.")
(defvar smoke-a8--seed-snapshot :unset
  "gethash of app:a8smoke right after `jetpacs--before-replay' ran.")
(defvar smoke-a8--welcome-floor :unset)
(defvar smoke-a8--ready nil)
(defvar smoke-a8--replay-summary nil)
(defvar smoke-a8--taps 0)

(defun smoke-a8--builder ()
  (jetpacs-column
   (jetpacs-text (format "A8 cold-start smoke — %s" smoke-a8--phase)
                 :style "headline")
   (jetpacs-text (format "taps this process: %d" smoke-a8--taps)
                 :style "caption")
   (jetpacs-button "visit row"
                   (jetpacs-action "a8smoke.visit"
                                   :when-offline 'queue :ttl-s 3600))))

(defun smoke-a8--await-live-tap ()
  "Print TAP-NOW, wait for one dispatch, assert the healthy path.
A tap against the snapshot this process just pushed carries the current
floor, so stale-p must answer nil, the handler must accept, and the
effect (a deferred re-push) must run — the seeded table must never
over-stale LIVE traffic."
  ;; If a replayed event was ACCEPTED during the barrier, its deferred
  ;; effect fired in SYNCING; the shell must have queued and drained it
  ;; at READY (jetpacs-shell--on-ready) — visible as a claimed revision
  ;; above the seeded floor with no physical tap yet.
  (smoke-a8--drain 3)
  (when (cl-find 'accepted smoke-a8--dispatches :key #'caddr)
    (smoke-a8--check "READY drained the SYNCING-deferred effect push"
                     (let ((rev (gethash "app:a8smoke"
                                         (ebp-client-revisions
                                          (jetpacs-client)))))
                       (and (integerp rev)
                            (> rev (or smoke-a8--seed-snapshot -1))))
                     (format "revision %S > seeded %S"
                             (gethash "app:a8smoke"
                                      (ebp-client-revisions (jetpacs-client)))
                             smoke-a8--seed-snapshot)))
  (princ "TAP-NOW\n")
  ;; Batch stdout is block-buffered when redirected to a file; the
  ;; orchestrator polls for this marker, so it must not sit in a stdio
  ;; buffer until exit.  `message' writes stderr, which is unbuffered.
  (message "TAP-NOW")
  (let ((before (length smoke-a8--dispatches)))
    (smoke-a8--drain 30 (lambda () (> (length smoke-a8--dispatches) before)))
    (let ((live (car smoke-a8--dispatches)))
      (smoke-a8--check "a live tap dispatched"
                       (> (length smoke-a8--dispatches) before))
      (when (> (length smoke-a8--dispatches) before)
        (smoke-a8--check "live tap was fresh -> accepted"
                         (and (not (cadr live)) (eq (caddr live) 'accepted))
                         (format "rev_seen %S -> %S, taps %d"
                                 (car live) (caddr live) smoke-a8--taps))
        ;; Its effect re-push: the claimed revision climbs again.
        (let ((before-rev (gethash "app:a8smoke"
                                   (ebp-client-revisions (jetpacs-client)))))
          (smoke-a8--drain 3)
          (smoke-a8--check "the live tap's effect re-pushed"
                           (let ((rev (gethash "app:a8smoke"
                                               (ebp-client-revisions
                                                (jetpacs-client)))))
                             (and (integerp rev)
                                  (or (null before-rev) (>= rev before-rev))
                                  (> rev (or smoke-a8--seed-snapshot -1))))
                           (format "revision %S"
                                   (gethash "app:a8smoke"
                                            (ebp-client-revisions
                                             (jetpacs-client))))))))))

(defun smoke-a8--register ()
  (with-jetpacs-owner "a8smoke"
    (jetpacs-defaction "a8smoke.visit"
                       (lambda (_args params)
                         (let* ((stale (and (jetpacs-event-stale-p params) t))
                                (status (if stale 'stale 'accepted)))
                           (push (list (plist-get params :revision_seen)
                                       stale status)
                                 smoke-a8--dispatches)
                           (unless stale
                             (cl-incf smoke-a8--taps)
                             ;; The effect: re-push, deferred per D2.
                             (run-at-time 0 nil #'jetpacs-shell-push
                                          (plist-get params :surface)))
                           status)))
    (jetpacs-shell-define-root "a8smoke" #'smoke-a8--builder
                               :required (equal smoke-a8--phase "phase2"))))

(defun smoke-a8--connect ()
  "ebp-connect + attach, with the production barrier plus our observer.
`jetpacs-connect' would install `jetpacs--before-replay' itself; calling
ebp-connect directly lets the smoke snapshot the table at the one
instant that discriminates the fix — inside the barrier, after the seed,
before the step-3 push's confirmation can raise it."
  (let ((client
         (ebp-connect
          "127.0.0.1" 8765
          :client-name "wsl-emacs" :client-version "30.1"
          :pairing-id "101112131415161718191a1b1c1d1e1f"
          :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
          :wants '("theme")
          :receipt-file smoke-a8--receipts
          :state-changed-function #'jetpacs--on-state-changed
          :before-replay-function
          (lambda (c)
            (setq smoke-a8--welcome-floor
                  (plist-get (plist-get (ebp-client-surfaces c) :app:a8smoke)
                             :revision))
            (jetpacs--before-replay c)
            (setq smoke-a8--seed-snapshot
                  (gethash "app:a8smoke" jetpacs--applied-revisions)))
          :after-replay-function
          (lambda (_c summary) (setq smoke-a8--replay-summary summary))
          :ready-function (lambda (_c) (setq smoke-a8--ready t)))))
    ;; Mirror `jetpacs-connect' exactly: it also installs the READY drain
    ;; for pushes SYNCING refused.  Forgetting this here is how the drain
    ;; check first "failed" on hardware — harness, not product.
    (when (fboundp 'jetpacs-shell--on-ready)
      (push #'jetpacs-shell--on-ready (ebp-client-ready-functions client)))
    (jetpacs-attach client)))

(defun smoke-a8--drain (secs &optional stop-fn)
  (let ((deadline (+ (float-time) secs)))
    (while (and (< (float-time) deadline)
                (not (and stop-fn (funcall stop-fn))))
      (accept-process-output nil 0.1))))

(smoke-a8--register)
(progn
  (smoke-a8--connect)
  (smoke-a8--drain 20 (lambda () smoke-a8--ready))
  (smoke-a8--check "session reaches READY" smoke-a8--ready)

  (pcase smoke-a8--phase
    ("phase1"
     ;; First run on a pairing: the surface may not exist yet, so the
     ;; welcome may report no floor.  Push and report what was claimed.
     (let ((rev (with-jetpacs-owner "a8smoke" (jetpacs-shell-push "a8smoke"))))
       (smoke-a8--drain 3)
       (smoke-a8--check "phase1 push claimed a revision" (integerp rev)
                        (format "revision %S" rev))
       ;; The orchestrator parses this line.
       (princ (format "A8_FLOOR=%d\n" rev)))
     ;; Die with the snapshot on screen: no close, no remove.  The
     ;; in-memory applied table is lost exactly as an OS kill loses it.
     (princ "phase1 dying now; tap the button while disconnected\n"))

    ("phase2"
     ;; The barrier already ran to reach READY; judge what it recorded.
     (smoke-a8--check "welcome reported the phase1 floor"
                      (and (integerp smoke-a8--welcome-floor)
                           (or (null smoke-a8--expect-floor)
                               (= smoke-a8--welcome-floor
                                  smoke-a8--expect-floor)))
                      (format "welcome %S, expected %S"
                              smoke-a8--welcome-floor smoke-a8--expect-floor))
     ;; THE fix assertion: at the barrier instant the table held the
     ;; welcome floor.  Pre-d11300e this was nil.
     (smoke-a8--check "seed adopted the floor INSIDE the barrier"
                      (and (integerp smoke-a8--seed-snapshot)
                           (equal smoke-a8--seed-snapshot
                                  smoke-a8--welcome-floor))
                      (format "seeded %S" smoke-a8--seed-snapshot))
     ;; The replayed offline tap: revision_seen = phase1 floor, which the
     ;; required step-3 push has outrun -> the handler must see stale.
     (smoke-a8--drain 10 (lambda () smoke-a8--dispatches))
     (let ((replayed (car (last smoke-a8--dispatches))))
       (smoke-a8--check "the offline tap replayed into the handler"
                        replayed
                        (and replayed (format "rev_seen %S" (car replayed))))
       (when replayed
         (smoke-a8--check "replayed event carried the phase1 revision_seen"
                          (equal (car replayed) smoke-a8--welcome-floor))
         (smoke-a8--check "stale-p gated the replayed event"
                          (and (cadr replayed) (eq (caddr replayed) 'stale))
                          (format "stale-p %S -> %S"
                                  (cadr replayed) (caddr replayed)))))
     (smoke-a8--check "replay backlog drained"
                      (and smoke-a8--replay-summary
                           (eql (plist-get smoke-a8--replay-summary :remaining)
                                0))
                      (format "summary %S" smoke-a8--replay-summary))
     ;; The healthy path: a live tap against the fresh snapshot.
     (smoke-a8--await-live-tap))

    ("live"
     ;; Standalone healthy-path pass: no replay expectations, just the
     ;; barrier seed plus one live tap.  Used when the phase2 window was
     ;; missed, or to re-verify the no-over-staling half on its own.
     (smoke-a8--check "seed adopted a floor INSIDE the barrier"
                      (integerp smoke-a8--seed-snapshot)
                      (format "seeded %S (welcome %S)"
                              smoke-a8--seed-snapshot smoke-a8--welcome-floor))
     (smoke-a8--await-live-tap))))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-a8--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-a8--fails))
(kill-emacs (if (zerop smoke-a8--fails) 0 1))

;;; smoke-a8-coldstart.el ends here
