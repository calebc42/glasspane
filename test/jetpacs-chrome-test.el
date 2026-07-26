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

(provide 'jetpacs-chrome-test)
;;; jetpacs-chrome-test.el ends here
