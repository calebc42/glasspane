;;; jetpacs-chrome-test.el --- JA-2c chrome kit exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JA-2c chrome half (docs/PLAN-jetpacs-apps.md, B6).  Stack pushes
;; are recorded at `ebp-client-surface-update'; view.switched drives the
;; REAL shell handler through `jetpacs--dispatch', proving the kit hook
;; is total under the no-prompts regime.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-chrome)

(defconst jetpacs-chrome-test--types
  ["text" "row" "column" "box" "spacer" "divider" "button" "text_input"
   "card" "icon" "icon_button" "lazy_column" "scaffold"])

(defun jetpacs-chrome-test--client (&optional profiles)
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jetpacs-chrome-receipts"))))
    (setf (ebp-client-state client) 'ready
          (ebp-client-profiles client)
          (or profiles
              `(:app (:node_types ,jetpacs-chrome-test--types
                      :builtins ["view.switch"] :features [])))
          (ebp-client-limits client) '(:max_frame_bytes 4194304))
    client))

(defmacro jetpacs-chrome-test--with (client-form &rest body)
  (declare (indent 1))
  `(let ((client ,client-form))
     (unwind-protect
         (progn (jetpacs-attach client) ,@body)
       (jetpacs-detach)
       (jetpacs-test-reset-state)
       (clrhash jetpacs-chrome--stacks))))

(defmacro jetpacs-chrome-test--recording (records &rest body)
  (declare (indent 1))
  `(let ((,records nil))
     (cl-letf (((symbol-function 'ebp-client-surface-update)
                (cl-function
                 (lambda (_c surface spec &rest keys)
                   (push (list surface spec keys) ,records)
                   42))))
       ,@body)))

;;;; Composition

(ert-deftest jetpacs-chrome-screen-shape ()
  (let ((json (jetpacs-node->canonical-json
               (jetpacs-chrome-screen "Files" (jetpacs-text "body")
                                      :back (jetpacs-view-switch "hub")))))
    ;; Load-bearing: back precedes the title; weight rides ON the title;
    ;; back is the view.switch BUILTIN.
    (should (string-match-p "arrow_back" json))
    (should (string-match-p "\"builtin\":\"view.switch\",\"view\":\"hub\"" json))
    (should (string-match-p "\"text\":\"Files\",\"weight\":1" json))
    (should (< (string-search "arrow_back" json)
               (string-search "\"Files\"" json))))
  ;; No back: exactly one top-bar child, no icon_button anywhere.
  (let ((json (jetpacs-node->canonical-json
               (jetpacs-chrome-screen "Hub" (jetpacs-text "b")))))
    (should-not (string-search "icon_button" json))))

(ert-deftest jetpacs-chrome-row-shape ()
  (let ((json (jetpacs-node->canonical-json
               (jetpacs-chrome-row "Docs" :subtitle "3 files" :icon "folder"
                                   :key "r1"
                                   :trailing (jetpacs-icon "chevron_right")
                                   :on-tap (jetpacs-action
                                            "files.open"
                                            :args '(:path "docs"))))))
    ;; :key survived (universal attr via with-attrs — the poc drop bug).
    (should (string-match-p "\"key\":\"r1\"" json))
    (should (string-match-p "\"weight\":1" json))
    (should (string-match-p "\"action\":\"files.open\"" json))
    (should (string-match-p "chevron_right" json))
    (should (string-match-p "\"style\":\"caption\"" json))))

;;;; The stack

(defun jetpacs-chrome-test--define (owner root-id)
  (with-jetpacs-owner owner
    (jetpacs-chrome-define-root
     owner root-id
     (lambda (back)
       (should-not back)
       (jetpacs-chrome-screen "Hub" (jetpacs-text "h"))))))

(ert-deftest jetpacs-chrome-stack-push-drives-builder ()
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "filesapp" "hub")
      (should (= 42 (jetpacs-chrome-push-screen
                     "filesapp" "detail"
                     (lambda (back)
                       (jetpacs-chrome-screen "Detail" (jetpacs-text "d")
                                              :back back)))))
      (pcase-let ((`(,surface ,spec ,keys) (car recs)))
        (should (equal surface "app:filesapp"))
        (should (equal (plist-get keys :current-view) "detail"))
        (should (equal (plist-get spec :initial_view) "detail"))
        (let ((views (plist-get spec :views)))
          (should (gethash "hub" views))
          (should (gethash "detail" views))
          ;; Detail's back targets hub.
          (should (string-match-p
                   "\"builtin\":\"view.switch\",\"view\":\"hub\""
                   (jetpacs-node->canonical-json (gethash "detail" views))))))
      ;; A third screen backs onto detail.
      (jetpacs-chrome-push-screen
       "filesapp" "deeper"
       (lambda (back)
         (should (equal (plist-get back :view) "detail"))
         (jetpacs-chrome-screen "Deeper" (jetpacs-text "x") :back back)))
      (should (equal (jetpacs-chrome-stack "filesapp")
                     '("deeper" "detail" "hub"))))))

(ert-deftest jetpacs-chrome-pop-and-reset ()
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "filesapp" "hub")
      (jetpacs-chrome-push-screen "filesapp" "detail"
                                  (lambda (back)
                                    (jetpacs-chrome-screen
                                     "D" (jetpacs-text "d") :back back)))
      (jetpacs-chrome-pop-screen "filesapp")
      (pcase-let ((`(,_s ,spec ,keys) (car recs)))
        (should (equal (plist-get keys :current-view) "hub"))
        (should-not (gethash "detail" (plist-get spec :views))))
      (should (equal (jetpacs-chrome-stack "filesapp") '("hub")))
      ;; Pop at the root: idempotent nil, no push.
      (let ((n (length recs)))
        (should-not (jetpacs-chrome-pop-screen "filesapp"))
        (should (= (length recs) n)))
      ;; Reset from deep.
      (jetpacs-chrome-push-screen "filesapp" "a" (lambda (_b) (jetpacs-text "a")))
      (jetpacs-chrome-push-screen "filesapp" "b" (lambda (_b) (jetpacs-text "b")))
      (jetpacs-chrome-reset-screens "filesapp")
      (should (equal (jetpacs-chrome-stack "filesapp") '("hub"))))))

(ert-deftest jetpacs-chrome-duplicate-id-truncates-and-replaces ()
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "filesapp" "hub")
      (jetpacs-chrome-push-screen "filesapp" "detail"
                                  (lambda (_b) (jetpacs-text "one")))
      (jetpacs-chrome-push-screen "filesapp" "deeper"
                                  (lambda (_b) (jetpacs-text "two")))
      (jetpacs-chrome-push-screen "filesapp" "detail"
                                  (lambda (_b) (jetpacs-text "Detail2")))
      (should (equal (jetpacs-chrome-stack "filesapp") '("detail" "hub")))
      (pcase-let ((`(,_s ,spec ,_k) (car recs)))
        (should (string-match-p
                 "Detail2"
                 (jetpacs-node->canonical-json
                  (gethash "detail" (plist-get spec :views)))))))))

(ert-deftest jetpacs-chrome-view-switched-truncates ()
  "Driven through the REAL registered shell handler: total under the
no-prompts regime, silent (no push), unknown views ignored."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "filesapp" "hub")
      (jetpacs-chrome-push-screen "filesapp" "detail"
                                  (lambda (_b) (jetpacs-text "d")))
      (jetpacs-chrome-push-screen "filesapp" "deeper"
                                  (lambda (_b) (jetpacs-text "x")))
      (let ((n (length recs)))
        (should (eq 'accepted
                    (jetpacs--dispatch
                     client '(:action "view.switched"
                              :surface "app:filesapp"
                              :args (:view "detail"))
                     (gethash "view.switched" jetpacs-action-handlers))))
        (should (equal (jetpacs-chrome-stack "filesapp") '("detail" "hub")))
        (should (= (length recs) n))
        ;; Unknown view: untouched.
        (jetpacs--dispatch client '(:action "view.switched"
                                    :surface "app:filesapp"
                                    :args (:view "nowhere"))
                           (gethash "view.switched" jetpacs-action-handlers))
        (should (equal (jetpacs-chrome-stack "filesapp")
                       '("detail" "hub")))))))

(ert-deftest jetpacs-chrome-two-surfaces-independent ()
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "appa" "hub-a")
      (jetpacs-chrome-test--define "appb" "hub-b")
      (jetpacs-chrome-push-screen "appa" "d1" (lambda (_b) (jetpacs-text "d")))
      (should (equal (nth 0 (car recs)) "app:appa"))
      (should (equal (jetpacs-chrome-stack "appb") '("hub-b")))
      (jetpacs--dispatch client '(:action "view.switched"
                                  :surface "app:appa" :args (:view "hub-a"))
                         (gethash "view.switched" jetpacs-action-handlers))
      (should (equal (jetpacs-chrome-stack "appa") '("hub-a")))
      (should (equal (jetpacs-chrome-stack "appb") '("hub-b"))))))

(ert-deftest jetpacs-chrome-background-refresh-omits-current-view ()
  "SPEC 13.4 conformance: a plain refresh names no current_view but the
snapshot still carries every view with initial_view at the stack top."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "filesapp" "hub")
      (jetpacs-chrome-push-screen "filesapp" "detail"
                                  (lambda (_b) (jetpacs-text "d")))
      (jetpacs-shell-push "filesapp")
      (pcase-let ((`(,_s ,spec ,keys) (car recs)))
        (should-not (plist-get keys :current-view))
        (should (equal (plist-get spec :initial_view) "detail"))
        (should (gethash "hub" (plist-get spec :views)))))))

(ert-deftest jetpacs-chrome-push-screen-validates-before-wire ()
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "filesapp" "hub")
      (should-error (jetpacs-chrome-push-screen "filesapp" "/sdcard/x"
                                                #'ignore))
      (should-error (jetpacs-chrome-push-screen "neverdefined" "s" #'ignore))
      (should (equal (jetpacs-chrome-stack "filesapp") '("hub")))
      (should (null recs)))))

(ert-deftest jetpacs-chrome-drill-adapter ()
  "The C7 adapter: minted id, deferred push, repeat-drill replace-top."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "filesapp" "hub")
      (let ((deferred '()))
        (cl-letf (((symbol-function 'run-at-time)
                   (lambda (_t _r fn &rest _) (push fn deferred) nil)))
          (should (jetpacs-chrome--drill
                   "app:filesapp"
                   (lambda () (list (jetpacs-text "body")))
                   "*hostile name*"))
          ;; Stack mutated synchronously; the push deferred.
          (should (= (length (jetpacs-chrome-stack "app:filesapp")) 2))
          (should (null recs))
          (funcall (car deferred))
          (should (= (length recs) 1))
          ;; Repeat drill with the SAME label: replace-top, not stacking.
          (jetpacs-chrome--drill "app:filesapp"
                                 (lambda () (list (jetpacs-text "again")))
                                 "*hostile name*")
          (should (= (length (jetpacs-chrome-stack "app:filesapp")) 2)))))))

(ert-deftest jetpacs-chrome-teardown-hook-drops-stacks ()
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (cl-letf (((symbol-function 'ebp-client-surface-remove)
               (cl-function (lambda (&rest _) 1))))
      (jetpacs-chrome-test--define "filesapp" "hub")
      (should (jetpacs-chrome-stack "filesapp"))
      (jetpacs-teardown-owner "filesapp")
      (should-not (jetpacs-chrome-stack "filesapp")))))


;;;; E1a: the poison transaction

(defun jetpacs-chrome-test--deep (n)
  "N nested columns — deep enough to trip GATE 5's max_node_depth.
The E1a poison vector must be one the per-view gate does NOT pre-run
\(E1b degrades GATE 1/4 failures to an error card before the push):
GATE 5 runs only on the assembled spec, so a too-deep screen still
reaches the push-level signal — the residual the transaction exists
for."
  (let ((node (jetpacs-text "leaf")))
    (dotimes (_ n) (setq node (jetpacs-column node)))
    node))

(defun jetpacs-chrome-test--gate-error (thunk)
  "THUNK's error message, or nil — the assertion must name WHICH gate
fired: a bare `should-error' here can pass on an unrelated signal."
  (condition-case err (progn (funcall thunk) nil)
    (error (error-message-string err))))

(defmacro jetpacs-chrome-test--clean-repush (&rest body)
  "Run BODY, then drop the repush queue and timer the tests arm."
  (declare (indent 0))
  `(unwind-protect (progn ,@body)
     (setq jetpacs-shell--repush-pending nil)
     (when (timerp jetpacs-shell--repush-timer)
       (cancel-timer jetpacs-shell--repush-timer)
       (setq jetpacs-shell--repush-timer nil))))

(ert-deftest jetpacs-chrome-push-screen-rolls-back-on-gate-failure ()
  "Transactional push: a screen the gates refuse never enters the model.
Pre-fix the mutated stack was KEPT, `jetpacs-chrome--build' rebuilt the
poisoned entry on every later push, and the surface was unpushable for
the process lifetime."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--clean-repush
      (jetpacs-chrome-test--recording recs
        (with-jetpacs-owner "filesapp"
          (jetpacs-chrome-define-root "filesapp" "hub"
                                      (lambda (_back)
                                        (jetpacs-chrome-screen
                                         "Hub" (jetpacs-text "hub")))))
        (should (= 42 (jetpacs-shell-push "app:filesapp")))
        ;; The bad screen: 25 nested columns trip GATE 5's depth cap on
        ;; the ASSEMBLED spec — the failure class the per-view gate does
        ;; not pre-run, so it reaches the push-level signal.
        (let ((msg (jetpacs-chrome-test--gate-error
                    (lambda ()
                      (jetpacs-chrome-push-screen
                       "app:filesapp" "bad"
                       (lambda (_back) (jetpacs-chrome-test--deep 25)))))))
          (should (string-match-p "max_node_depth" msg)))
        ;; Rolled back: the model never held the refused screen…
        (should (equal (jetpacs-chrome-stack "app:filesapp") '("hub")))
        ;; …the consumed repush entry was restored…
        (should (member "app:filesapp" jetpacs-shell--repush-pending))
        ;; …and the surface is still pushable.
        (should (= 42 (jetpacs-shell-push "app:filesapp")))))))

(ert-deftest jetpacs-chrome-reentrant-rollback-restores-the-old-builder ()
  "The `setcdr' sharing trap: replacing an EXISTING id mutated a cons
shared with the saved stack, so a rollback restored the shape but kept
the poisoned builder.  The replace branch must CONS fresh."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--clean-repush
      (jetpacs-chrome-test--recording recs
        (with-jetpacs-owner "filesapp"
          (jetpacs-chrome-define-root "filesapp" "hub"
                                      (lambda (_back)
                                        (jetpacs-chrome-screen
                                         "Hub" (jetpacs-text "hub")))))
        (jetpacs-chrome-push-screen "app:filesapp" "detail"
                                    (lambda (back)
                                      (jetpacs-chrome-screen
                                       "Detail" (jetpacs-text "ok")
                                       :back back)))
        ;; Re-entrant push of the SAME id with a gate-failing builder.
        (should (jetpacs-chrome-test--gate-error
                 (lambda ()
                   (jetpacs-chrome-push-screen
                    "app:filesapp" "detail"
                    (lambda (_back) (jetpacs-chrome-test--deep 25))))))
        (should (equal (jetpacs-chrome-stack "app:filesapp")
                       '("detail" "hub")))
        ;; The OLD builder survived the rollback: pushable, and the wire
        ;; carries the good detail screen.
        (should (= 42 (jetpacs-shell-push "app:filesapp")))
        (should (string-match-p "\"ok\""
                                (jetpacs-node->canonical-json
                                 (cadr (car recs)))))))))

(ert-deftest jetpacs-chrome-pop-commits-even-when-the-push-fails ()
  "The other half of the design rule: a REMOVAL can only shrink the
stack, so it commits unconditionally — the push loss is logged and
requeued, never signalled."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--clean-repush
      (jetpacs-chrome-test--recording recs
        (with-jetpacs-owner "filesapp"
          (jetpacs-chrome-define-root "filesapp" "hub"
                                      (lambda (_back)
                                        (jetpacs-chrome-screen
                                         "Hub" (jetpacs-text "hub")))))
        (jetpacs-chrome-push-screen "app:filesapp" "detail"
                                    (lambda (back)
                                      (jetpacs-chrome-screen
                                       "Detail" (jetpacs-text "d")
                                       :back back)))
        ;; Make the NEXT push fail regardless of stack content.
        (cl-letf (((symbol-function 'jetpacs-shell-push)
                   (lambda (&rest _) (error "gate says no"))))
          (should-not (jetpacs-chrome-pop-screen "app:filesapp")))
        ;; The pop COMMITTED and queued the re-render.
        (should (equal (jetpacs-chrome-stack "app:filesapp") '("hub")))
        (should (member "app:filesapp" jetpacs-shell--repush-pending))))))

(ert-deftest jetpacs-chrome-drill-failure-does-not-poison-the-stack ()
  "Deferring the drill's push dodged the rejected-flattening but NOT the
poison: the failed entry stayed and every later push of the surface
signalled.  The deferred failure must roll the insert back."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--clean-repush
      (jetpacs-chrome-test--recording recs
        (with-jetpacs-owner "filesapp"
          (jetpacs-chrome-define-root "filesapp" "hub"
                                      (lambda (_back)
                                        (jetpacs-chrome-screen
                                         "Hub" (jetpacs-text "hub")))))
        (should (jetpacs-chrome--drill
                 "app:filesapp"
                 (lambda () (list (jetpacs-chrome-test--deep 25)))
                 "*bad buffer*"))
        ;; Drain the deferred push (run-at-time 0).
        (cl-loop repeat 20
                 until (= 1 (length (jetpacs-chrome-stack "app:filesapp")))
                 do (accept-process-output nil 0.02))
        (should (equal (jetpacs-chrome-stack "app:filesapp") '("hub")))
        (should (member "app:filesapp" jetpacs-shell--repush-pending))
        (should (= 42 (jetpacs-shell-push "app:filesapp")))))))

(ert-deftest jetpacs-chrome-repush-drain-is-isolated-per-surface ()
  "One owner's gate failure must not drop every other owner's queued
re-render: the debounce drain isolates per surface, like the READY
drain always has."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--clean-repush
      (jetpacs-chrome-test--recording recs
        (with-jetpacs-owner "bad"
          (jetpacs-shell-define-root "bad"
                                     (lambda () (jetpacs-progress :value 1))))
        (with-jetpacs-owner "good"
          (jetpacs-shell-define-root "good" (lambda () (jetpacs-text "g"))))
        (setq recs nil)
        (jetpacs-shell--schedule-repush "app:bad")
        (jetpacs-shell--schedule-repush "app:good")
        ;; Fire the debounce deterministically.
        (let ((timer jetpacs-shell--repush-timer))
          (should (timerp timer))
          (funcall (timer--function timer)))
        (should (equal (mapcar #'car recs) '("app:good")))))))

(ert-deftest jetpacs-chrome-async-flush-is-isolated-per-owner ()
  "The async settle drain has the same obligation as the repush drain."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--clean-repush
      (jetpacs-chrome-test--recording recs
        (with-jetpacs-owner "bad"
          (jetpacs-shell-define-root "bad"
                                     (lambda () (jetpacs-progress :value 1))))
        (with-jetpacs-owner "good"
          (jetpacs-shell-define-root "good" (lambda () (jetpacs-text "g"))))
        (setq recs nil)
        (setq jetpacs-async--pending-owners '("good" "bad"))
        (jetpacs-async--flush-push)
        (should (equal (mapcar #'car recs) '("app:good")))))))


;;;; E1b: a broken screen costs its own view

(defun jetpacs-chrome-test--view-json (recs view-id)
  "The canonical JSON of VIEW-ID's node in the newest recorded push."
  (let* ((spec (cadr (car recs)))
         (views (plist-get spec :views)))
    (jetpacs-node->canonical-json (gethash view-id views))))

(ert-deftest jetpacs-chrome-broken-screen-costs-its-own-view ()
  "One signalling builder costs its view — never the multi_view.
Pre-fix the whole spec degraded to a bare column: GATE 2 nils
`current_view', the Companion clears the retained view, and the back
affordance and navigation state died together on every rebuild.  The
card carries the error SYMBOL only: `error-message-string' embeds the
offending datum and SPEC 13.2 persists this text on the device."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (with-jetpacs-owner "filesapp"
        (jetpacs-chrome-define-root "filesapp" "hub"
                                    (lambda (_back)
                                      (jetpacs-chrome-screen
                                       "Hub" (jetpacs-text "hub-alive")))))
      (jetpacs-chrome-push-screen
       "app:filesapp" "detail"
       (lambda (_back) (error "boom: /home/secret/passwords.org")))
      (let* ((spec (cadr (car recs)))
             (keys (car (cddr (car recs)))))
        ;; Still a multi_view; navigation forced to the broken screen.
        (should (plist-member spec :views))
        (should (equal (plist-get keys :current-view) "detail"))
        ;; The healthy screen is untouched…
        (should (string-match-p "hub-alive"
                                (jetpacs-chrome-test--view-json recs "hub")))
        ;; …the broken one is the card, WITH its back escape…
        (let ((card (jetpacs-chrome-test--view-json recs "detail")))
          (should (string-match-p "failed to build" card))
          (should (string-match-p "view.switch" card))
          ;; …and the secret never reached the wire (SPEC 23.3/13.2).
          (should-not (string-match-p "passwords" card))
          (should-not (string-match-p "passwords"
                                      (jetpacs-node->canonical-json spec))))))))

(ert-deftest jetpacs-chrome-non-node-builder-degrades-the-same-way ()
  "A builder that RETURNS garbage (nil, a string) is the same failure
class as one that signals — `jetpacs-multi-view' would signal on it
after the loop, collapsing the whole spec."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (with-jetpacs-owner "filesapp"
        (jetpacs-chrome-define-root "filesapp" "hub"
                                    (lambda (_back)
                                      (jetpacs-chrome-screen
                                       "Hub" (jetpacs-text "hub-alive")))))
      (jetpacs-chrome-push-screen "app:filesapp" "detail"
                                  (lambda (_back) nil))
      (should (plist-member (cadr (car recs)) :views))
      (should (string-match-p "failed to build"
                              (jetpacs-chrome-test--view-json recs "detail"))))))

(ert-deftest jetpacs-chrome-dead-screen-refunds-its-budget ()
  "A screen that spends SPEC 4.5 budget and then dies refunds it —
nothing it spent ships, and without the refund a broken screen silently
truncates every healthy screen built after it."
  (jetpacs-chrome-test--with
      (jetpacs-chrome-test--client
       `(:app (:node_types ["text" "row" "column" "box" "spacer" "divider"
                            "button" "text_input" "rich_text"]
               :builtins ["view.switch"] :features [])))
    (setf (ebp-client-limits client)
          '(:max_frame_bytes 4194304 :max_rich_spans 200))
    (jetpacs-chrome-test--recording recs
      (with-jetpacs-owner "filesapp"
        ;; The ROOT (built first, bottom-first walk) spends 150 spans and
        ;; dies; the pushed screen then asks for 120.
        (jetpacs-chrome-define-root
         "filesapp" "hub"
         (lambda (_back)
           (jetpacs-buffer-spend-spans
            (cl-loop repeat 150 collect (jetpacs-span "x")))
           (error "hub died after spending"))))
      (jetpacs-chrome-push-screen
       "app:filesapp" "detail"
       (lambda (_back)
         (jetpacs-column
          (jetpacs-rich-text
           (jetpacs-buffer-spend-spans
            (cl-loop repeat 120 collect (jetpacs-span "y")))))))
      (let ((detail (jetpacs-chrome-test--view-json recs "detail")))
        ;; All 120 spans shipped: the dead root's 150 were refunded.
        (should (= 120 (cl-count ?y detail)))))))

(ert-deftest jetpacs-chrome-unadvertised-type-costs-its-own-view ()
  "The per-view GATE 1 pre-run: an unadvertised node type is the MOST
likely screen failure in practice (every skin pre-checks
`jetpacs-node-advertised-p' because of it), and it does not signal in
the builder — it would signal in GATE 1 on the ASSEMBLED spec, after
E1a rolls back, leaving a healthy surface but a dead navigation.
Pre-running the gate per view turns it into that screen's error card."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (with-jetpacs-owner "filesapp"
        (jetpacs-chrome-define-root "filesapp" "hub"
                                    (lambda (_back)
                                      (jetpacs-chrome-screen
                                       "Hub" (jetpacs-text "hub-alive")))))
      ;; "progress" is not in the fixture profile.
      (should (= 42 (jetpacs-chrome-push-screen
                     "app:filesapp" "detail"
                     (lambda (_back) (jetpacs-progress :value 0.5)))))
      (should (string-match-p "failed to build"
                              (jetpacs-chrome-test--view-json recs "detail")))
      (should (string-match-p "hub-alive"
                              (jetpacs-chrome-test--view-json recs "hub"))))))

(ert-deftest jetpacs-chrome-ungranted-editor-costs-its-own-view ()
  "The per-view GATE 4 pre-run: a synchronized editor without the
`editor.sync' grant passes GATE 1 (the TYPE is advertised) and would
poison the surface at the push-level amendment gate."
  (jetpacs-chrome-test--with
      (jetpacs-chrome-test--client
       `(:app (:node_types ["text" "row" "column" "box" "spacer" "divider"
                            "button" "text_input" "editor"]
               :builtins ["view.switch"] :features [])))
    (setf (ebp-client-granted client) ["theme"])   ; no editor.sync
    (jetpacs-chrome-test--recording recs
      (with-jetpacs-owner "filesapp"
        (jetpacs-chrome-define-root "filesapp" "hub"
                                    (lambda (_back)
                                      (jetpacs-chrome-screen
                                       "Hub" (jetpacs-text "hub-alive")))))
      (should (= 42 (jetpacs-chrome-push-screen
                     "app:filesapp" "detail"
                     (lambda (_back)
                       (jetpacs-column
                        (jetpacs-editor "ed1" :document "doc1"))))))
      (should (string-match-p "failed to build"
                              (jetpacs-chrome-test--view-json recs "detail"))))))

(ert-deftest jetpacs-chrome-error-card-drops-back-when-unadvertised ()
  "The degrade path must not out-fail the failure it degrades: against
a (nonconforming) profile without the `view.switch' builtin, the card
retries WITHOUT its Back button rather than tripping GATE 1 itself."
  (jetpacs-chrome-test--with
      (jetpacs-chrome-test--client
       `(:app (:node_types ,jetpacs-chrome-test--types
               :builtins [] :features [])))
    (jetpacs-chrome-test--recording recs
      (with-jetpacs-owner "filesapp"
        (jetpacs-chrome-define-root "filesapp" "hub"
                                    (lambda (_back)
                                      (jetpacs-column
                                       (jetpacs-text "hub-alive")))))
      (should (= 42 (jetpacs-chrome-push-screen
                     "app:filesapp" "detail"
                     (lambda (_back) (error "boom")))))
      (let ((card (jetpacs-chrome-test--view-json recs "detail")))
        (should (string-match-p "failed to build" card))
        (should-not (string-match-p "view.switch" card))))))


;;;; E1e: the teardown sweep list

(ert-deftest jetpacs-chrome-teardown-sweeps-secondary-stacks ()
  "The hook reads the PRE-SWEEP surface list.  Recomputing after the
sweep sees only the D1 primary — the secondary's stack survived, pinned
builder closures, and answered a later drill with false success."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (with-jetpacs-owner "notes"
        (jetpacs-chrome-define-root "notes" "hub"
                                    (lambda (_b) (jetpacs-column
                                                  (jetpacs-text "hub"))))
        (jetpacs-chrome-define-root "app:notes-detail" "d"
                                    (lambda (_b) (jetpacs-column
                                                  (jetpacs-text "d")))))
      (should (gethash "app:notes-detail" jetpacs-chrome--stacks))
      ;; The stub client has no jsonrpc connection: absorb the tombstones.
      (cl-letf (((symbol-function 'ebp-client-surface-remove)
                 (cl-function (lambda (&rest _) 1))))
        (jetpacs-teardown-owner "notes"))
      ;; BOTH stacks swept — primary and secondary.
      (should-not (gethash "app:notes" jetpacs-chrome--stacks))
      (should-not (gethash "app:notes-detail" jetpacs-chrome--stacks))
      ;; And the published list is not leaked past the extent.
      (should-not jetpacs-teardown-surfaces))))

(ert-deftest jetpacs-chrome-drill-refuses-a-stackless-surface ()
  "The drill seam promises it never signals: a torn-down (or simply
non-chrome) surface answers nil so the navigator runs its documented
degrade, instead of turning a handler's answer into a permanent
rejected."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (should-not (jetpacs-chrome--drill
                 "app:nochrome"
                 (lambda () (list (jetpacs-text "x")))
                 "*probe*"))))

(ert-deftest jetpacs-chrome-push-screen-signals-on-a-torn-down-surface ()
  "Owning the E1e delta: push-screen on a torn-down SECONDARY surface
now signals `no chrome stack', matching what the primary always did —
the divergence WAS the bug.  Callers pushing across a live-reload
teardown must use a nil-tolerant path (the drill seam)."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (with-jetpacs-owner "notes"
        (jetpacs-chrome-define-root "notes" "hub"
                                    (lambda (_b) (jetpacs-column
                                                  (jetpacs-text "hub"))))
        (jetpacs-chrome-define-root "app:notes-detail" "d"
                                    (lambda (_b) (jetpacs-column
                                                  (jetpacs-text "d")))))
      (cl-letf (((symbol-function 'ebp-client-surface-remove)
                 (cl-function (lambda (&rest _) 1))))
        (jetpacs-teardown-owner "notes"))
      (should-error (jetpacs-chrome-push-screen "app:notes-detail" "later"
                                                #'ignore)))))

(ert-deftest jetpacs-chrome-buffer-local-hook-spares-global-subscribers ()
  "`run-hook-wrapped', not `dolist': a buffer-local `add-hook' puts `t'
in the hook value, and (funcall t owner) — swallowed by the isolation —
would silently drop every GLOBAL subscriber after it.
The hook is LET-BOUND, never setq'd: a setq in a test wipes the module
subscribers for the rest of the batch."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (let ((global-ran nil)
          (jetpacs-teardown-functions jetpacs-teardown-functions))
      (add-hook 'jetpacs-teardown-functions
                (lambda (_o) (setq global-ran t)))
      (with-temp-buffer
        (add-hook 'jetpacs-teardown-functions #'ignore nil t)
        (jetpacs-teardown-owner "alpha"))
      (should global-ran))))


;;;; E1d: current_view — the belief and the debt

(defun jetpacs-chrome-test--nav-fixture ()
  "A hub root + one pushed detail screen under the recording stub."
  (with-jetpacs-owner "filesapp"
    (jetpacs-chrome-define-root "filesapp" "hub"
                                (lambda (_b) (jetpacs-column
                                              (jetpacs-text "hub"))))))

(ert-deftest jetpacs-chrome-current-view-accessor-no-longer-lies ()
  "`jetpacs-shell-current-view' is written by the PUSH path now, not
only by `view.switched' — which the Companion generates only for the
`view.switch' builtin, so after every Emacs-driven navigation the
public accessor answered a stale view."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--nav-fixture)
      (jetpacs-chrome-push-screen "app:filesapp" "detail"
                                  (lambda (back)
                                    (jetpacs-chrome-screen
                                     "D" (jetpacs-text "d") :back back)))
      (should (equal (jetpacs-shell-current-view "filesapp") "detail"))
      ;; A background refresh still OMITS current_view on the wire
      ;; (SPEC 13.4) and does not disturb the belief.
      (jetpacs-shell-push "app:filesapp")
      (should-not (plist-get (car (cddr (car recs))) :current-view))
      (should (equal (jetpacs-shell-current-view "filesapp") "detail")))))

(ert-deftest jetpacs-chrome-refused-navigation-is-reasserted ()
  "A W10-refused navigation is OWED, not lost: the next push for that
surface re-asserts the exact view once.  Drives ebp's REAL held branch
— the refusal concludes synchronously inside the send."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--nav-fixture))
    ;; REAL send path, ceiling held: the push is refused locally.
    (setf (ebp-client-outstanding client) ebp-overload-hold)
    (jetpacs-chrome-push-screen "app:filesapp" "detail"
                                (lambda (back)
                                  (jetpacs-chrome-screen
                                   "D" (jetpacs-text "d") :back back)))
    (should (equal (gethash "app:filesapp" jetpacs-shell--unasserted-view)
                   "detail"))
    ;; The ceiling clears; a PLAIN push (any retry path) re-asserts it.
    (setf (ebp-client-outstanding client) 0)
    (jetpacs-chrome-test--recording recs
      (jetpacs-shell-push "app:filesapp")
      (should (equal (plist-get (car (cddr (car recs))) :current-view)
                     "detail")))))

(ert-deftest jetpacs-chrome-two-refused-views-latest-wins ()
  "One slot, latest write wins: refusing X then Y leaves only Y owed —
X must not resurrect and yank the user backwards."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--nav-fixture))
    (setf (ebp-client-outstanding client) ebp-overload-hold)
    (jetpacs-chrome-push-screen "app:filesapp" "d1"
                                (lambda (back)
                                  (jetpacs-chrome-screen
                                   "1" (jetpacs-text "1") :back back)))
    (jetpacs-chrome-push-screen "app:filesapp" "d2"
                                (lambda (back)
                                  (jetpacs-chrome-screen
                                   "2" (jetpacs-text "2") :back back)))
    (should (equal (gethash "app:filesapp" jetpacs-shell--unasserted-view)
                   "d2"))
    (setf (ebp-client-outstanding client) 0)
    (jetpacs-chrome-test--recording recs
      (jetpacs-shell-push "app:filesapp")
      (should (equal (plist-get (car (cddr (car recs))) :current-view)
                     "d2")))))

(ert-deftest jetpacs-chrome-device-back-cancels-the-owed-view ()
  "The Companion's own word is newer than the debt: a `view.switched'
after a refused navigation cancels it — re-asserting would yank the
user off the screen they chose."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--nav-fixture))
    (setf (ebp-client-outstanding client) ebp-overload-hold)
    (jetpacs-chrome-push-screen "app:filesapp" "detail"
                                (lambda (back)
                                  (jetpacs-chrome-screen
                                   "D" (jetpacs-text "d") :back back)))
    (should (gethash "app:filesapp" jetpacs-shell--unasserted-view))
    ;; The user taps back on the device.
    (jetpacs--dispatch client '(:action "view.switched"
                                :args (:view "hub")
                                :surface "app:filesapp")
                       (gethash "view.switched" jetpacs-action-handlers))
    (should-not (gethash "app:filesapp" jetpacs-shell--unasserted-view))
    (setf (ebp-client-outstanding client) 0)
    (jetpacs-chrome-test--recording recs
      (jetpacs-shell-push "app:filesapp")
      (should-not (plist-get (car (cddr (car recs))) :current-view)))))

(ert-deftest jetpacs-chrome-syncing-push-owes-its-view ()
  "The SECOND refusal site: a push during the SYNCING replay window is
dropped before the wire too, and the READY drain re-pushes with no
view — a replayed handler's deferred navigation must ride the same
debt."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--nav-fixture))
    (setf (ebp-client-state client) 'syncing)
    (jetpacs-chrome-push-screen "app:filesapp" "detail"
                                (lambda (back)
                                  (jetpacs-chrome-screen
                                   "D" (jetpacs-text "d") :back back)))
    (should (equal (gethash "app:filesapp" jetpacs-shell--unasserted-view)
                   "detail"))
    (should (member "app:filesapp" jetpacs-shell--repush-pending))
    (setf (ebp-client-state client) 'ready)
    (jetpacs-chrome-test--recording recs
      (jetpacs-shell--on-ready client)
      (should (equal (plist-get (car (cddr (car recs))) :current-view)
                     "detail")))))


;;;; E1c: SPEC 16.1 — one document, unique node ids

(ert-deftest jetpacs-chrome-minted-ids-route-around-each-other ()
  "Two screens minting the same base in one document: the FIRST keeps
the stable id (its SPEC 13.6 draft survives), only the duplicate moves.
Pre-fix the duplicate shipped, the Companion answered 1201 for the
whole update, and 13.2 froze the surface on the old snapshot."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (with-jetpacs-owner "filesapp"
        (jetpacs-chrome-define-root
         "filesapp" "hub"
         (lambda (_b) (jetpacs-column
                       (jetpacs-text-input
                        (jetpacs-claim-node-id "field")
                        :hint "hub")))))
      (should (= 42 (jetpacs-chrome-push-screen
                     "app:filesapp" "detail"
                     (lambda (back)
                       (jetpacs-chrome-screen
                        "D" (jetpacs-text-input
                             (jetpacs-claim-node-id "field")
                             :hint "drill")
                        :back back)))))
      (let ((ids (sort (jetpacs--collect-node-ids (cadr (car recs)) nil)
                       #'string<)))
        (should (equal ids '("field" "field-1")))))))

(ert-deftest jetpacs-chrome-literal-id-collision-costs-the-screen ()
  "A LITERAL authored id repeated across screens is a screen failure,
not a surface failure: the colliding screen degrades to its error card
and the first claimant ships untouched."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (with-jetpacs-owner "filesapp"
        (jetpacs-chrome-define-root
         "filesapp" "hub"
         (lambda (_b) (jetpacs-column
                       (jetpacs-text-input "search" :hint "hub")))))
      (should (= 42 (jetpacs-chrome-push-screen
                     "app:filesapp" "detail"
                     (lambda (back)
                       (jetpacs-chrome-screen
                        "D" (jetpacs-text-input "search" :hint "dup")
                        :back back)))))
      ;; Hub keeps its input; the detail view is the card.
      (should (string-match-p "\"search\""
                              (jetpacs-chrome-test--view-json recs "hub")))
      (should (string-match-p "failed to build"
                              (jetpacs-chrome-test--view-json recs "detail")))
      ;; And the assembled document carries the id exactly once.
      (should (= 1 (cl-count "search"
                             (jetpacs--collect-node-ids (cadr (car recs)) nil)
                             :test #'equal))))))

(ert-deftest jetpacs-chrome-gate-1d-is-the-non-chrome-floor ()
  "GATE 1d: a plain root builder shipping a literal duplicate is caught
at the push — the sender MUST is loud, typed, and names no user data."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (with-jetpacs-owner "plain"
        (jetpacs-shell-define-root
         "plain" (lambda () (jetpacs-column
                             (jetpacs-text-input "dup" :hint "a")
                             (jetpacs-text-input "dup" :hint "b")))))
      (should-error (jetpacs-shell-push "app:plain")
                    :type 'jetpacs-duplicate-node-id))))

(ert-deftest jetpacs-chrome-claim-node-id-properties ()
  "The promoted minter's three hard properties: identity outside a
document build; the 4.4 length clamp (a 128-char base suffixes to a
VALID identifier, not a 130-char reject); and t-normalization (a seeded
name stores t, and a real base equal to one must not reach
(format \"%s-%d\" base t))."
  (let ((jetpacs-node-id-claims nil))
    (should (equal (jetpacs-claim-node-id "free") "free")))
  (let ((jetpacs-node-id-claims (make-hash-table :test #'equal))
        (long (make-string 128 ?a)))
    (should (equal (jetpacs-claim-node-id long) long))
    (let ((second (jetpacs-claim-node-id long)))
      (should (jetpacs--identifier-p second))
      (should (<= (length second) 128))
      (should (string-suffix-p "-1" second))))
  (let ((jetpacs-node-id-claims (make-hash-table :test #'equal)))
    (puthash "seeded" t jetpacs-node-id-claims)
    (should (equal (jetpacs-claim-node-id "seeded") "seeded-1"))))

(ert-deftest jetpacs-chrome-earlier-literal-seeds-later-mints ()
  "A later screen's MINT routes around an earlier screen's LITERAL: the
root's ids are seeded into the claim table, so the drill's minted base
suffixes instead of colliding into a card."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (with-jetpacs-owner "filesapp"
        (jetpacs-chrome-define-root
         "filesapp" "hub"
         (lambda (_b) (jetpacs-column
                       (jetpacs-text-input "comint-x" :hint "literal")))))
      (should (= 42 (jetpacs-chrome-push-screen
                     "app:filesapp" "detail"
                     (lambda (back)
                       (jetpacs-chrome-screen
                        "D" (jetpacs-text-input
                             (jetpacs-claim-node-id "comint-x")
                             :hint "minted")
                        :back back)))))
      ;; NOT a card — the mint moved aside.
      (should-not (string-match-p "failed to build"
                                  (jetpacs-chrome-test--view-json
                                   recs "detail")))
      (let ((ids (sort (jetpacs--collect-node-ids (cadr (car recs)) nil)
                       #'string<)))
        (should (equal ids '("comint-x" "comint-x-1")))))))


;;;; E1f: the stack bound and the fixed-limit gates

(ert-deftest jetpacs-chrome-stack-is-bounded-root-pinned ()
  "SPEC 22.3: the stack renders at most `jetpacs-chrome-max-screens'
screens.  The ROOT is pinned — it is the registered fallback — and the
lowest surviving screen back-targets it.  The bound applies inside
`--stack-insert' BEFORE the single puthash, so the E1a undo thunk's
`eq' guard still matches: a failed push after an eviction still rolls
back."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--clean-repush
      (jetpacs-chrome-test--recording recs
        (jetpacs-chrome-test--nav-fixture)
        (dotimes (i 5)
          (jetpacs-chrome-push-screen
           "app:filesapp" (format "s%d" (1+ i))
           (lambda (back)
             (jetpacs-chrome-screen "S" (jetpacs-text "s") :back back))))
        ;; Newest two plus the pinned root.
        (should (equal (jetpacs-chrome-stack "app:filesapp")
                       '("s5" "s4" "hub")))
        ;; The lowest surviving screen back-targets the ROOT, and the
        ;; root keeps no back arrow.
        (let* ((spec (cadr (car recs)))
               (views (plist-get spec :views))
               (json4 (jetpacs-node->canonical-json (gethash "s4" views)))
               (jsonh (jetpacs-node->canonical-json (gethash "hub" views))))
          (should (string-match-p "\"view\":\"hub\"" json4))
          (should-not (string-match-p "arrow_back" jsonh)))
        ;; Eviction did not defeat the transaction: a refused push still
        ;; rolls back to exactly this stack.
        (should-error (jetpacs-chrome-push-screen
                       "app:filesapp" "bad"
                       (lambda (_b) (jetpacs-chrome-test--deep 25))))
        (should (equal (jetpacs-chrome-stack "app:filesapp")
                       '("s5" "s4" "hub")))))))

(ert-deftest jetpacs-chrome-gate-counts-nodes-and-children ()
  "The two fixed SPEC 4.5 limits nothing counted: total nodes per
snapshot and children per node.  Both are hard Companion rejects."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      ;; 10001 children under one column: the children cap fires.
      (let* ((kids (cl-loop repeat 10001 collect (jetpacs-text "x")))
             (spec (apply #'jetpacs-column kids))
             (msg (jetpacs-chrome-test--gate-error
                   (lambda () (jetpacs-shell-push "app:demo" :spec spec)))))
        (should (string-match-p "max_children_per_node" msg)))
      ;; Two columns of 5001 each: children pass, the node TOTAL fires.
      (let* ((spec (jetpacs-column
                    (apply #'jetpacs-column
                           (cl-loop repeat 5001 collect (jetpacs-text "x")))
                    (apply #'jetpacs-column
                           (cl-loop repeat 5001 collect (jetpacs-text "x")))))
             (msg (jetpacs-chrome-test--gate-error
                   (lambda () (jetpacs-shell-push "app:demo" :spec spec)))))
        (should (string-match-p "max_nodes_per_snapshot" msg))))))

(ert-deftest jetpacs-chrome-depth-counts-every-nesting-member ()
  "Depth matches the Companion's validator: a typed node reached from
ANY member is one level deeper — `:children' has no special status.
Pre-fix, 25 box-in-box nestings through a non-children member measured
depth 1 and sailed past the gate straight into a 1201."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (let ((deep '(:t "text" :text "leaf")))
        (dotimes (_ 25)
          (setq deep (list :t "box" :item deep)))
        (let ((msg (jetpacs-chrome-test--gate-error
                    (lambda () (jetpacs-shell-push "app:demo" :spec deep)))))
          (should (string-match-p "max_node_depth" msg)))))))

(ert-deftest jetpacs-chrome-screen-carries-drawer-and-bottom-bar ()
  "The CHROME-VOCABULARY slots pass through to the scaffold: DRAWER
(app destinations, hamburger Companion-added) and BOTTOM-BAR (the
view switcher)."
  (let* ((screen (jetpacs-chrome-screen
                  "T" (jetpacs-text "body")
                  :drawer (jetpacs-text "d")
                  :bottom-bar (jetpacs-text "bb"))))
    (should (equal (plist-get (plist-get screen :drawer) :text) "d"))
    (should (equal (plist-get (plist-get screen :bottom_bar) :text) "bb"))))

(ert-deftest jetpacs-chrome-dock-rides-every-screen-and-defers-to-own ()
  "The dock seam: `jetpacs-chrome-dock-function''s node becomes the
`bottom_bar' of every stacked scaffold screen — the view switcher
persists across drills — while a screen authoring its own bar wins."
  (let ((jetpacs-chrome-dock-function (lambda (_s) (jetpacs-text "dock"))))
    (unwind-protect
        (progn
          (with-jetpacs-owner "dockdemo"
            (jetpacs-chrome-define-root "dockdemo" "root"
                                        (lambda (back)
                                          (jetpacs-chrome-screen
                                           "R" (jetpacs-text "r") :back back))))
          (jetpacs-chrome--stack-insert
           "app:dockdemo" "own"
           (lambda (back)
             (jetpacs-chrome-screen "O" (jetpacs-text "o") :back back
                                    :bottom-bar (jetpacs-text "mine"))))
          (jetpacs-chrome--stack-insert
           "app:dockdemo" "leaf"
           (lambda (back)
             (jetpacs-chrome-screen "L" (jetpacs-text "l") :back back)))
          (let* ((mv (jetpacs-chrome--build "app:dockdemo"))
                 (views (plist-get mv :views)))
            (should (equal (plist-get (plist-get (gethash "root" views)
                                                 :bottom_bar)
                                      :text)
                           "dock"))
            (should (equal (plist-get (plist-get (gethash "leaf" views)
                                                 :bottom_bar)
                                      :text)
                           "dock"))
            (should (equal (plist-get (plist-get (gethash "own" views)
                                                 :bottom_bar)
                                      :text)
                           "mine"))))
      (jetpacs-chrome-remove "app:dockdemo"))))

(ert-deftest jetpacs-chrome-items-dock-wears-bottom-bar-on-compact ()
  "The data dock: on a compact width the destinations become a real M3
navigation bar — the catalog-proven item composition, selection as the
active-indicator pill.  Disconnected `jetpacs-window-class' already
answers compact, which is also why every OTHER chrome test stays
untouched by the adaptive seam."
  (let ((jetpacs-chrome-dock-items-function
         (lambda (_s)
           (list (list :label "A" :icon "home"
                       :on-tap (jetpacs-action "jetpacs.noop") :selected t)
                 (list :label "B" :icon "code"
                       :on-tap (jetpacs-action "jetpacs.noop"))))))
    (unwind-protect
        (progn
          (with-jetpacs-owner "itemsdemo"
            (jetpacs-chrome-define-root "itemsdemo" "root"
                                        (lambda (_back)
                                          (jetpacs-chrome-screen
                                           "R" (jetpacs-text "r")))))
          (let* ((mv (jetpacs-chrome--build "app:itemsdemo"))
                 (view (gethash "root" (plist-get mv :views)))
                 (bar (plist-get view :bottom_bar))
                 (tabs (plist-get bar :children)))
            (should-not (plist-member view :rail))
            (should (equal (plist-get bar :t) "row"))
            (should (equal (plist-get bar :height) 80))
            (should (= 2 (length tabs)))
            ;; The selected item wears the secondary_container active
            ;; indicator; the unselected one must not.
            (should (string-match-p "secondary_container"
                                    (format "%S" (aref tabs 0))))
            (should-not (string-match-p "secondary_container"
                                        (format "%S" (aref tabs 1))))))
      (jetpacs-chrome-remove "app:itemsdemo"))))

(ert-deftest jetpacs-chrome-items-dock-wears-rail-on-expanded ()
  "The data dock on an expanded width: the SAME destinations ride the
scaffold rail slot as a navigation_rail, and no bottom bar is injected
— the NavigationSuiteScaffold swap (SPEC 20.1.1 x 17.6)."
  (let ((jetpacs-chrome-dock-items-function
         (lambda (_s)
           (list (list :label "A" :icon "home"
                       :on-tap (jetpacs-action "jetpacs.noop") :selected t)
                 (list :label "B" :icon "code"
                       :on-tap (jetpacs-action "jetpacs.noop"))))))
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-window-class)
                   (lambda (axis)
                     (if (eq axis :width) "expanded" "medium"))))
          (with-jetpacs-owner "raildemo"
            (jetpacs-chrome-define-root "raildemo" "root"
                                        (lambda (_back)
                                          (jetpacs-chrome-screen
                                           "R" (jetpacs-text "r")))))
          (let* ((mv (jetpacs-chrome--build "app:raildemo"))
                 (view (gethash "root" (plist-get mv :views)))
                 (rail (plist-get view :rail)))
            (should-not (plist-member view :bottom_bar))
            (should (equal (plist-get rail :t) "navigation_rail"))))
      (jetpacs-chrome-remove "app:raildemo"))))

(ert-deftest jetpacs-chrome-node-dock-outranks-items-and-stays-bottom ()
  "`jetpacs-chrome-dock-function' is the raw-node override: when both
are set the finished node wins, and it stays a bottom bar even on an
expanded window — only the data form can be re-authored into a rail."
  (let ((jetpacs-chrome-dock-function (lambda (_s) (jetpacs-text "raw")))
        (jetpacs-chrome-dock-items-function
         (lambda (_s) (list (list :label "A" :icon "home"
                                  :on-tap (jetpacs-action "jetpacs.noop"))))))
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-window-class)
                   (lambda (_axis) "expanded")))
          (with-jetpacs-owner "rawdemo"
            (jetpacs-chrome-define-root "rawdemo" "root"
                                        (lambda (_back)
                                          (jetpacs-chrome-screen
                                           "R" (jetpacs-text "r")))))
          (let* ((mv (jetpacs-chrome--build "app:rawdemo"))
                 (view (gethash "root" (plist-get mv :views))))
            (should-not (plist-member view :rail))
            (should (equal (plist-get (plist-get view :bottom_bar) :text)
                           "raw"))))
      (jetpacs-chrome-remove "app:rawdemo"))))

(ert-deftest jetpacs-chrome-dock-failure-degrades-to-no-dock ()
  "A signalling dock builder costs the dock, never the surface."
  (let ((jetpacs-chrome-dock-function (lambda (_s) (error "boom"))))
    (unwind-protect
        (progn
          (with-jetpacs-owner "dockdemo2"
            (jetpacs-chrome-define-root "dockdemo2" "root"
                                        (lambda (back)
                                          (jetpacs-chrome-screen
                                           "R" (jetpacs-text "r") :back back))))
          (let* ((mv (jetpacs-chrome--build "app:dockdemo2"))
                 (views (plist-get mv :views)))
            (should (gethash "root" views))
            (should-not (plist-get (gethash "root" views) :bottom_bar))))
      (jetpacs-chrome-remove "app:dockdemo2"))))

(provide 'jetpacs-chrome-test)
;;; jetpacs-chrome-test.el ends here
