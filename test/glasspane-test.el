;;; glasspane-test.el --- Glasspane app ladder gates -*- lexical-binding: t; -*-

;; The per-rung LOCAL GATE suite of docs/PLAN-glasspane-app.md: every
;; rung adds its NAMED assertions here, and test/run-tests.sh runs the
;; whole file after the M3 stanza.  G0's three gates pin registration,
;; home serialization, and unload hygiene.

;;; Code:

(require 'ert)
(require 'glasspane)

;;;; G0 — skeleton, registration, harness wiring

(ert-deftest glasspane-test-registers ()
  "Requiring the app REGISTERS it: the owner verb is in the action
table, the app registry entry carries the identity, and the home
surface is the one the chrome root was defined on — so `app.open'
lands somewhere that exists (the M3 suite's shape)."
  (should (gethash "glasspane.home" jetpacs-action-handlers))
  (let ((entry (assoc glasspane-owner jetpacs-apps--registry)))
    (should entry)
    (should (equal (plist-get (cdr entry) :label) "Glasspane"))
    (should (member glasspane-owner (plist-get (cdr entry) :surfaces)))
    (should (equal (jetpacs-apps--home-surface entry) glasspane-owner))))

(ert-deftest glasspane-test-home-serializes ()
  "The placeholder home screen BUILDS and its body round-trips the
canonical wire encoding — the same bar every later rung's screens must
clear, established while the screen is one card tall."
  (let ((screen (glasspane-home-screen nil)))
    (should screen)
    ;; A chrome screen IS a scaffold node — serialize it whole.
    (let ((json (jetpacs-node->canonical-json screen)))
      (should (stringp json))
      (should (string-search "Glasspane" json)))))

(ert-deftest glasspane-test-dock-item-shape ()
  "The dock destination carries the chrome item shape and tracks
selection against the app's own surface."
  (let* ((home (jetpacs-shell-surface-for glasspane-owner))
         (items (glasspane--dock-items home)))
    (should (= (length items) 1))
    (let ((item (car items)))
      (should (equal (plist-get item :label) "Glasspane"))
      (should (equal (plist-get item :icon) glasspane-icon))
      (should (plist-get item :on-tap))
      (should (eq (plist-get item :selected) t)))
    ;; From a foreign surface the row is not selected.
    (should-not (plist-get (car (glasspane--dock-items "app:elsewhere"))
                           :selected))))

(ert-deftest glasspane-test-unload-clean ()
  "Unregistration leaves no verb, no claim, no registry entry — the
sibling modules' verbs included, since they register through
`glasspane-register' rather than at their own load — and is undone by
`glasspane-register' (the live-reload path), which this test restores
so suite order never matters."
  (let ((verbs '("glasspane.home"
                 "org.clock.out" "org.clock.switch" "org.clock.in-last"
                 "config.sync" "glasspane.packages.install")))
    (unwind-protect
        (progn
          (glasspane-unregister)
          (dolist (name verbs)
            (should-not (gethash name jetpacs-action-handlers))
            ;; The claim record goes with the handler: teardown-owner
            ;; and unregister must agree on what "glasspane" owns.
            (should-not (jetpacs--owner-of "action" name)))
          (should-not (assoc glasspane-owner jetpacs-apps--registry))
          (should-not (alist-get "Packages" jetpacs-settings-registry
                                 nil nil #'equal)))
      (glasspane-register))
    (dolist (name verbs)
      (should (gethash name jetpacs-action-handlers))
      (should (equal (jetpacs--owner-of "action" name) glasspane-owner)))
    (should (alist-get "Packages" jetpacs-settings-registry
                       nil nil #'equal))))

;;;; G1 — data layer: glasspane-org.el

(ert-deftest glasspane-test-org-extraction ()
  "Agenda, todo and level-1 extraction over a throwaway vault; every
item's ref is an `ebp-org-ref-at-point' plist (S5 groundwork) — the
UI layer mints tokens from these, so the shape is load-bearing."
  (let* ((vault (make-temp-file "glasspane-vault" t))
         (file (expand-file-name "tasks.org" vault))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots nil)
         (today (format-time-string "%Y-%m-%d")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: Tasks\n\n"
                    "* TODO Water the garden :home:\n"
                    (format "SCHEDULED: <%s>\n" today)
                    "* TODO Call the bank\n"
                    "* Reference notes\n"
                    "** Not level one\n"))
          (ebp-org-cache-invalidate)
          (let* ((items (glasspane-org--agenda-items 'day))
                 (hit (cl-find-if
                       (lambda (it)
                         (equal (alist-get 'headline it) "Water the garden"))
                       items)))
            (should hit)
            (should (equal (alist-get 'date hit) today))
            (let ((ref (alist-get 'ref hit)))
              (should (equal (plist-get ref :headline) "Water the garden"))
              (should (equal (plist-get ref :file) (file-truename file)))
              (should (integerp (plist-get ref :pos)))))
          (let ((items (glasspane-org--todo-items (list file))))
            (should (= (length items) 2))
            (dolist (it items)
              (should (stringp (plist-get (alist-get 'ref it) :headline)))))
          (should (equal (mapcar (lambda (it) (alist-get 'headline it))
                                 (glasspane-org--file-heading-items file))
                         '("Water the garden" "Call the bank"
                           "Reference notes"))))
      (ebp-org-cache-invalidate)
      (dolist (buf (buffer-list))
        (let ((f (buffer-file-name buf)))
          (when (and f (string-prefix-p (file-name-as-directory
                                         (file-truename vault))
                                        (file-truename f)))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf))))
      (delete-directory vault t))))

(ert-deftest glasspane-test-org-query-routing ()
  "With vulpea absent every query runs the built-in interpreter, and
the memo is KEYED on the action: a repeat never re-runs the action,
and a different key over the same tree never serves its payload
(the P1-12 rule `glasspane-org--query' rides)."
  (let* ((vault (make-temp-file "glasspane-vault" t))
         (file (expand-file-name "tasks.org" vault))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots nil))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: Tasks\n\n"
                    "* TODO Water the garden :home:\n"
                    "* TODO Call the bank\n"
                    "* Reference notes\n"))
          (ebp-org-cache-invalidate)
          ;; Visit the file BEFORE the first query: the freshness stamp
          ;; includes visiting buffers' ticks, so the buffer the first
          ;; query itself opens would honestly bust the repeat.
          (find-file-noselect file)
          (should-not (glasspane-org--vulpea-p))
          (let ((calls 0)
                (real (symbol-function 'glasspane-org--heading-item-at)))
            (cl-letf (((symbol-function 'glasspane-org--heading-item-at)
                       (lambda () (cl-incf calls) (funcall real))))
              (let ((first (glasspane-org--search "todo:TODO")))
                (should (= (length first) 2))
                (should (= calls 2))
                (should (equal (glasspane-org--search "todo:TODO") first))
                (should (= calls 2))))
            (let ((tree (ebp-org-parse-query "todo:TODO")))
              (should (equal (ebp-org-query 'glasspane 'other-action tree
                                            (lambda () 'other))
                             '(other other)))
              (should (= (length (glasspane-org--query tree)) 2))))
          (let ((hits (glasspane-org--search "garden")))
            (should (= (length hits) 1))
            (should (equal (alist-get 'headline (car hits))
                           "Water the garden"))))
      (ebp-org-cache-invalidate)
      (dolist (buf (buffer-list))
        (let ((f (buffer-file-name buf)))
          (when (and f (string-prefix-p (file-name-as-directory
                                         (file-truename vault))
                                        (file-truename f)))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf))))
      (delete-directory vault t))))

(ert-deftest glasspane-test-org-filter-items ()
  "The sparse filter narrows by the ONE grammar at each item's own
heading; the empty query is the identity; malformed and unsupported
queries SIGNAL — an empty result must mean \"nothing matched\"."
  (let* ((vault (make-temp-file "glasspane-vault" t))
         (file (expand-file-name "tasks.org" vault))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots nil))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: Tasks\n\n"
                    "* TODO Water the garden :home:\n"
                    "* TODO Call the bank\n"))
          (ebp-org-cache-invalidate)
          (let ((items (glasspane-org--todo-items (list file))))
            (should (= (length items) 2))
            (should (equal (glasspane-org--filter-items items "") items))
            (let ((kept (glasspane-org--filter-items items "tags:home")))
              (should (= (length kept) 1))
              (should (equal (alist-get 'headline (car kept))
                             "Water the garden")))
            (should-error (glasspane-org--filter-items items "(todo")
                          :type 'user-error)
            (should-error (glasspane-org--filter-items items "(clocked)")
                          :type 'user-error)))
      (ebp-org-cache-invalidate)
      (dolist (buf (buffer-list))
        (let ((f (buffer-file-name buf)))
          (when (and f (string-prefix-p (file-name-as-directory
                                         (file-truename vault))
                                        (file-truename f)))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf))))
      (delete-directory vault t))))

(ert-deftest glasspane-test-org-reminder-horizon ()
  "Only timed items inside the horizon become reminders, shaped as the
SPEC 18.6 plists `jetpacs-reminders-set' consumes: every :id is a
SPEC 4.4 identifier even for spaced headlines/paths (a raw headline
would reject the WHOLE set), and one entry surfacing twice at one
instant (scheduled + deadline) yields ONE alarm — a duplicate :id also
rejects the set.  The agenda arm is stubbed so the clock math is
deterministic."
  (let* ((in2h (time-add nil (* 2 3600)))
         (in72h (time-add nil (* 72 3600)))
         (d2 (format-time-string "%Y-%m-%d" in2h))
         (hm2 (format-time-string "%H:%M" in2h))
         (d72 (format-time-string "%Y-%m-%d" in72h))
         (hm72 (format-time-string "%H:%M" in72h))
         (items `(((headline . "Water the garden") (time . ,hm2) (date . ,d2)
                   (type . "scheduled") (file . "/v/my tasks.org") (pos . 42))
                  ((headline . "Water the garden") (time . ,hm2) (date . ,d2)
                   (type . "deadline") (file . "/v/my tasks.org") (pos . 42))
                  ((headline . "No alarm") (date . ,d2)
                   (type . "scheduled") (file . "/v/my tasks.org") (pos . 90))
                  ((headline . "Far") (time . ,hm72) (date . ,d72)
                   (type . "scheduled") (file . "/v/my tasks.org") (pos . 7)))))
    (cl-letf (((symbol-function 'glasspane-org--agenda-items)
               (lambda (&optional _span start-day) (unless start-day items))))
      (let ((rs (glasspane-org--upcoming-reminders)))
        (should (= (length rs) 1))
        (let ((r (car rs)))
          (should (equal (plist-get r :title) "Water the garden"))
          (should (jetpacs-identifier-p (plist-get r :id)))
          (should (equal (plist-get r :body) (format "%s · scheduled" hm2)))
          (should (equal (plist-get r :at_ms)
                         (truncate (* 1000 (float-time
                                            (org-time-string-to-time
                                             (concat d2 " " hm2))))))))
        ;; Distinct entries never share an id (file+pos+instant ride in).
        (let ((far (car (last (glasspane-org--upcoming-reminders (* 4 24))))))
          (should (jetpacs-identifier-p (plist-get far :id)))
          (should-not (equal (plist-get far :id)
                             (plist-get (car rs) :id)))))
      (should (= (length (glasspane-org--upcoming-reminders (* 4 24))) 2)))))

(ert-deftest glasspane-test-org-timestamp-hooks ()
  "The CREATED/MODIFIED stampers attach at app enable, do their work on
save, and detach when the app's owner is torn down — a bare `require'
never mutates the user's global org hooks."
  (let* ((vault (make-temp-file "glasspane-vault" t))
         (file (expand-file-name "note.org" vault)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: Note\n#+MODIFIED: [2000-01-01 Sat 00:00]\n\n"
                    "* Heading\n"))
          (glasspane-org-install-hooks)
          (should (member #'glasspane-org--before-save-timestamps
                          before-save-hook))
          (should (member #'glasspane-org--heading-created-property
                          org-insert-heading-hook))
          (should (member #'glasspane-org--heading-modified-property
                          org-property-changed-functions))
          (should (member #'glasspane-org--todo-modified-property
                          org-after-todo-state-change-hook))
          (should (member #'glasspane-org--on-teardown
                          jetpacs-teardown-functions))
          (with-current-buffer (find-file-noselect file)
            (goto-char (point-max))
            (insert "body line\n")
            (let ((save-silently t)) (save-buffer))
            (goto-char (point-min))
            (should (re-search-forward "^#\\+CREATED: \\[[0-9]\\{4\\}-" nil t))
            (goto-char (point-min))
            (should (re-search-forward "^#\\+MODIFIED: \\[" nil t))
            (goto-char (point-min))
            (should-not (search-forward "2000-01-01" nil t))
            (goto-char (point-min))
            (re-search-forward "^\\* Heading")
            (glasspane-org--heading-created-property)
            (should (org-entry-get (point) "CREATED"))
            (glasspane-org--heading-modified-property "FOO")
            (should (org-entry-get (point) "MODIFIED")))
          ;; A foreign owner's teardown leaves them attached...
          (glasspane-org--on-teardown "someone-else")
          (should (member #'glasspane-org--before-save-timestamps
                          before-save-hook))
          ;; ...the app's own removes every one.
          (glasspane-org--on-teardown glasspane-owner)
          (should-not (member #'glasspane-org--before-save-timestamps
                              before-save-hook))
          (should-not (member #'glasspane-org--heading-created-property
                              org-insert-heading-hook))
          (should-not (member #'glasspane-org--heading-modified-property
                              org-property-changed-functions))
          (should-not (member #'glasspane-org--todo-modified-property
                              org-after-todo-state-change-hook))
          (should-not (member #'glasspane-org--on-teardown
                              jetpacs-teardown-functions)))
      (glasspane-org-remove-hooks)
      (dolist (buf (buffer-list))
        (let ((f (buffer-file-name buf)))
          (when (and f (string-prefix-p (file-name-as-directory
                                         (file-truename vault))
                                        (file-truename f)))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf))))
      (delete-directory vault t))))

(ert-deftest glasspane-test-org-roots-refusal ()
  "File access rides the ebp-org root policy: outside the roots signals
`ebp-org-refused' (the UI layer's \\='rejected), a vanished file
`ebp-org-unresolved' (\\='stale) — and the filter, a predicate, just
answers nil."
  (let* ((vault (make-temp-file "glasspane-vault" t))
         (inside (expand-file-name "in.org" vault))
         (outside (make-temp-file "glasspane-outside" nil ".org"))
         (org-directory vault)
         (org-agenda-files (list inside))
         (ebp-org-roots nil))
    (unwind-protect
        (progn
          (with-temp-file inside (insert "#+TITLE: In\n* Here\n"))
          (with-temp-file outside (insert "#+TITLE: Out\n* TODO Elsewhere\n"))
          (ebp-org-cache-invalidate)
          (should-error (glasspane-org--file-heading-items outside)
                        :type 'ebp-org-refused)
          (should-error (glasspane-org--heading-at 1 outside)
                        :type 'ebp-org-refused)
          (should-error (glasspane-org--file-heading-items
                         (expand-file-name "gone.org" vault))
                        :type 'ebp-org-unresolved)
          (should (= (length (glasspane-org--file-heading-items inside)) 1))
          (should-not (glasspane-org--filter-items
                       `(((headline . "Elsewhere") (file . ,outside) (pos . 1)))
                       "todo:TODO")))
      (ebp-org-cache-invalidate)
      (dolist (buf (buffer-list))
        (let ((f (buffer-file-name buf)))
          (when (and f (string-prefix-p (file-name-as-directory
                                         (file-truename vault))
                                        (file-truename f)))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf))))
      (when (file-exists-p outside) (delete-file outside))
      (delete-directory vault t))))

;;;; G1 — data layer: glasspane-vulpea.el

(ert-deftest glasspane-test-vulpea-register-noop ()
  "With vulpea ABSENT — `vulpea-db-register-extractor' unbound, this
harness's permanent condition — registration is a SILENT no-op: no
error, nothing logged, and `glasspane-vulpea--registered' stays nil so
the first real registration is still owed when vulpea does arrive.
Loading the worker-lib beforehand must itself have had no side effects
(definitions only — the flag is untouched by load)."
  (require 'glasspane-vulpea)
  ;; The premise the gate names: this Emacs has no vulpea.
  (should-not (fboundp 'vulpea-db-register-extractor))
  (should-not glasspane-vulpea--registered)
  (let ((log-before (with-current-buffer (messages-buffer) (buffer-string))))
    (glasspane-vulpea-register)
    ;; Silent: the no-op arm neither signals nor messages.
    (should (equal (with-current-buffer (messages-buffer) (buffer-string))
                   log-before)))
  (should-not glasspane-vulpea--registered))

;;;; G2 — services: glasspane-clock.el

(ert-deftest glasspane-test-clock-notification-shape ()
  "The chronometer SurfaceSpec is SPEC 18.5-shaped: the elapsed timer
is meta `:chronometer' `:base_ms' (epoch millis, an integer), the
buttons live in meta `:actions' (a vector — the notification node set
has no button), every action carries a non-drop offline policy WITH
its mandatory ttl, and the whole spec round-trips the canonical wire
encoding."
  (require 'glasspane-clock)
  (cl-letf (((symbol-function 'org-clock-is-active) (lambda () t)))
    (let* ((org-clock-current-task "Water the garden")
           (org-clock-start-time (time-subtract nil 90))
           (spec (glasspane-clock-notification-spec))
           (meta (plist-get spec :meta))
           (chrono (plist-get meta :chronometer))
           (actions (plist-get meta :actions)))
      ;; The body is inside the notification profile's node set.
      (should (equal (plist-get (plist-get spec :body) :t) "text"))
      (should (eq (plist-get meta :ongoing) t))
      (should (equal (plist-get meta :category) "stopwatch"))
      (should (integerp (plist-get chrono :base_ms)))
      (should (= (plist-get chrono :base_ms)
                 (truncate (* 1000 (float-time org-clock-start-time)))))
      (should (vectorp actions))
      (should (= (length actions) 2))
      ;; Most important first: the platform may show fewer (SPEC 18.5).
      (should (equal (mapcar (lambda (a) (plist-get a :label))
                             (append actions nil))
                     '("Clock out" "Switch task")))
      (seq-doseq (entry actions)
        (let ((tap (plist-get entry :on_tap)))
          (should (member (plist-get tap :action)
                          '("org.clock.out" "org.clock.switch")))
          ;; No client in this harness, so `offline.wake' is ungranted:
          ;; the descriptor degrades wake -> queue (amendment #85 would
          ;; void the surface at the push gate) and still carries the
          ;; ttl every non-drop policy requires (SPEC 14.1 / plan T4).
          (should (equal (plist-get tap :when_offline) "queue"))
          (should (integerp (plist-get tap :ttl_s)))
          (should (<= 1 (plist-get tap :ttl_s) 604800))))
      (let ((json (jetpacs-node->canonical-json spec)))
        (should (stringp json))
        (should (string-search "\"base_ms\"" json))
        (should (string-search "\"actions\"" json))
        (should (string-search "Water the garden" json))))))

(ert-deftest glasspane-test-clock-handler-matrix ()
  "Every clock verb answers a SPEC 14.4 status over faked org-clock
state: out with no clock is `stale' (the notification outlived
reality), out with a running clock is `accepted' with the clock
buffer's save deferred through the ebp-org funnel, switch is a
definitive `rejected' until a real picker exists, and in-last maps
success/signal to `accepted'/`rejected'."
  (require 'glasspane-clock)
  ;; out, no clock -> stale.
  (cl-letf (((symbol-function 'org-clock-is-active) (lambda () nil)))
    (should (eq (glasspane-clock--on-out nil nil) 'stale)))
  ;; out, running -> accepted; `org-clock-out' ran; the save was
  ;; deferred IN the clock buffer (captured before out cleared markers).
  (with-temp-buffer
    (let ((m (point-marker)) (saved nil) (outed nil))
      (cl-letf (((symbol-function 'org-clock-is-active) (lambda () m))
                ((symbol-function 'org-clock-out)
                 (lambda (&rest _) (setq outed t)))
                ((symbol-function 'ebp-org-defer-save)
                 (lambda () (push (current-buffer) saved))))
        (let ((org-clock-marker m))
          (should (eq (glasspane-clock--on-out nil nil) 'accepted))
          (should outed)
          (should (equal saved (list (current-buffer))))))))
  ;; switch -> rejected: v1's `org-clock-goto' jump is a desktop
  ;; effect the phone cannot observe (plan G2).
  (should (eq (glasspane-clock--on-switch nil nil) 'rejected))
  ;; in-last: success -> accepted; a signal (empty history, or a
  ;; prompt dying under the no-prompt regime) -> rejected.
  (cl-letf (((symbol-function 'org-clock-in-last) (lambda (&rest _) t)))
    (let ((org-clock-marker (make-marker)))
      (should (eq (glasspane-clock--on-in-last nil nil) 'accepted))))
  (cl-letf (((symbol-function 'org-clock-in-last)
             (lambda (&rest _) (user-error "No last clock"))))
    (should (eq (glasspane-clock--on-in-last nil nil) 'rejected))))

(ert-deftest glasspane-test-clock-replayed-tap-dispatch ()
  "A durable clock tap replayed during SYNCING — after an Emacs restart,
SPEC 10.3 step 4, BEFORE the READY hook (step 5) re-claims the
notification root — reaches the handler's matrix instead of dying at
the D1 owned-surface gate: `rejected' there is PERMANENT (SPEC 14.4),
deleting the receipt while the clock keeps running.  The org.clock.*
verbs are global (:any-surface), so the full dispatch with the wire
surface and NO prior `glasspane-clock--assert' answers the matrix's
`stale'/`accepted'."
  (require 'glasspane-clock)
  ;; The replay premise: this session holds no live claim on the
  ;; notification surface, exactly like a fresh restart.
  (should-not (jetpacs-owned-surface-p glasspane-clock-surface "glasspane"))
  (dolist (name '("org.clock.out" "org.clock.switch" "org.clock.in-last"))
    (should (plist-get (jetpacs-action-schema name) :any-surface)))
  (let ((handler (gethash "org.clock.out" jetpacs-action-handlers)))
    (should handler)
    ;; No clock survives the restart -> the matrix's honest `stale'.
    (cl-letf (((symbol-function 'org-clock-is-active) (lambda () nil)))
      (should (eq (jetpacs--dispatch
                   nil (list :action "org.clock.out"
                             :surface glasspane-clock-surface
                             :args nil)
                   handler)
                  'stale)))
    ;; A clock still running -> the replayed clock-out lands `accepted'.
    (with-temp-buffer
      (let ((m (point-marker)) (outed nil))
        (cl-letf (((symbol-function 'org-clock-is-active) (lambda () m))
                  ((symbol-function 'org-clock-out)
                   (lambda (&rest _) (setq outed t)))
                  ((symbol-function 'ebp-org-defer-save) (lambda () t)))
          (let ((org-clock-marker m))
            (should (eq (jetpacs--dispatch
                         nil (list :action "org.clock.out"
                                   :surface glasspane-clock-surface
                                   :args nil)
                         handler)
                        'accepted))
            (should outed)))))))

(ert-deftest glasspane-test-clock-grant-degrade ()
  "With `surfaces.notification' ungranted — or no client at all,
`jetpacs-granted-p' fails closed — the mirror degrades WHOLE and
SILENT: no root registered, no push, no signal (the push gate would
error); and retire never tombstones a surface this session never
asserted."
  (require 'glasspane-clock)
  (let ((pushes 0) (roots 0) (removes 0))
    (cl-letf (((symbol-function 'jetpacs-granted-p) (lambda (&rest _) nil))
              ((symbol-function 'jetpacs-shell-push)
               (lambda (&rest _) (cl-incf pushes)))
              ((symbol-function 'jetpacs-shell-define-root)
               (lambda (&rest _) (cl-incf roots)))
              ((symbol-function 'jetpacs-shell-remove-root)
               (lambda (&rest _) (cl-incf removes)))
              ((symbol-function 'org-clock-is-active) (lambda () t)))
      (let ((glasspane-clock--live nil)
            (org-clock-current-task "Task")
            (org-clock-start-time (current-time)))
        (glasspane-clock--assert)
        (glasspane-clock--on-ready nil)
        (should-not glasspane-clock--live)
        (glasspane-clock--retire)
        (should (= roots 0))
        (should (= pushes 0))
        (should (= removes 0))))))

;;;; G2 — services: glasspane-config.el

(ert-deftest glasspane-test-config-sync-ensure-load ()
  "Over a throwaway `user-emacs-directory': a missing subtree loads as
a silent no-op; ensure CREATES it once (the full managed set) and
thereafter only loads — a user's edit to a seeded file survives;
loads run in name order with user extras sorted in; sync is the
explicit reset that clobbers the edit.  `load' is stubbed to a
recorder so the managed org payloads never execute in the harness."
  (let* ((tmp (make-temp-file "glasspane-ued" t))
         (user-emacs-directory (file-name-as-directory tmp))
         (dir (glasspane-config-dir))
         (managed (expand-file-name "capture-templates.el" dir))
         (loads nil))
    (unwind-protect
        (cl-letf (((symbol-function 'load)
                   (lambda (file &rest _) (push file loads) t)))
          ;; The subtree key is the plan's pinned app-local path.
          (should (equal dir (file-name-as-directory
                              (expand-file-name "jetpacs/apps/glasspane"
                                                user-emacs-directory))))
          ;; Missing subtree: load is a no-op, nothing signals.
          (glasspane-config-load)
          (should-not loads)
          ;; Ensure's create arm: the managed set is written and loaded.
          (glasspane-config-ensure)
          (should (equal (directory-files dir nil "\\.el\\'")
                         '("capture-templates.el" "org-defaults.el")))
          (should (equal (mapcar #'file-name-nondirectory (reverse loads))
                         '("capture-templates.el" "org-defaults.el")))
          ;; Create-ONCE: an existing subtree is loaded, never rewritten.
          (write-region ";; user edit" nil managed nil 'silent)
          (setq loads nil)
          (glasspane-config-ensure)
          (should (equal (mapcar #'file-name-nondirectory (reverse loads))
                         '("capture-templates.el" "org-defaults.el")))
          (should (equal (with-temp-buffer
                           (insert-file-contents managed)
                           (buffer-string))
                         ";; user edit"))
          ;; Name order holds with a user extra in the subtree.
          (write-region ";; extra" nil (expand-file-name "zz-extra.el" dir)
                        nil 'silent)
          (setq loads nil)
          (glasspane-config-load)
          (should (equal (mapcar #'file-name-nondirectory (reverse loads))
                         '("capture-templates.el" "org-defaults.el"
                           "zz-extra.el")))
          ;; Sync is the explicit reset: managed content comes back.
          (should (equal (glasspane-config-sync) dir))
          (should (string-prefix-p ";;; capture-templates.el"
                                   (with-temp-buffer
                                     (insert-file-contents managed)
                                     (buffer-string)))))
      (delete-directory tmp t))))

(ert-deftest glasspane-test-config-sync-accepted ()
  "The registered config.sync verb writes SYNCHRONOUSLY — both managed
files are on disk before the handler answers \\='accepted — notifies
inline (queue/raise, never blocking), and pushes only in the deferred
continuation: zero pushes inside the dispatch extent (D2), exactly one
when the continuation runs."
  (let* ((tmp (make-temp-file "glasspane-ued" t))
         (user-emacs-directory (file-name-as-directory tmp))
         (handler (gethash "config.sync" jetpacs-action-handlers))
         (notified nil)
         (pushes 0)
         (continuations nil))
    (should handler)
    (unwind-protect
        (cl-letf (((symbol-function 'load) (lambda (&rest _) t))
                  ((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &rest _) (push text notified)))
                  ((symbol-function 'jetpacs-shell-push)
                   (lambda (&rest _) (cl-incf pushes) nil))
                  ((symbol-function 'jetpacs-flow-continue)
                   (lambda (fn) (push fn continuations) nil)))
          (should (eq (funcall handler nil (list :surface "app:glasspane"))
                      'accepted))
          (let ((dir (glasspane-config-dir)))
            (should (file-exists-p
                     (expand-file-name "capture-templates.el" dir)))
            (should (file-exists-p
                     (expand-file-name "org-defaults.el" dir))))
          (should (= (length notified) 1))
          (should (string-match-p "App defaults refreshed" (car notified)))
          (should (= pushes 0))
          (should (= (length continuations) 1))
          (funcall (car continuations))
          (should (= pushes 1)))
      (delete-directory tmp t))))

;;;; G2 — services: glasspane-packages.el

(require 'glasspane-packages)

(ert-deftest glasspane-test-packages-wanted-drops-vulpea ()
  "The closed set is exactly the four engines with glasspane-pack's
folded floors, and a build without SQLite drops vulpea from the wanted
list — no install can help it there — while search and review stay."
  (should (equal glasspane-packages--set
                 '((org-ql    . "0.7")
                   (vulpea    . "2.0")
                   (org-srs   . nil)
                   (ef-themes . nil))))
  (cl-letf (((symbol-function 'sqlite-available-p) (lambda () nil)))
    (should-not (assq 'vulpea (glasspane-packages--wanted)))
    (should (equal (mapcar #'car (glasspane-packages--wanted))
                   '(org-ql org-srs ef-themes))))
  (cl-letf (((symbol-function 'sqlite-available-p) (lambda () t)))
    (should (equal (glasspane-packages--wanted) glasspane-packages--set))))

(ert-deftest glasspane-test-packages-batch-noop ()
  "In batch — `noninteractive' t, this suite's permanent condition —
the auto-install gate schedules nothing and never marks the session
attempted, even with every other condition forced open: CI must never
reach for MELPA."
  (should noninteractive)
  (let ((glasspane-packages-auto-install t)
        (glasspane-packages--attempted nil)
        (timers 0))
    (cl-letf (((symbol-function 'glasspane-packages--missing)
               (lambda () '(org-ql)))
              ((symbol-function 'run-with-idle-timer)
               (lambda (&rest _) (cl-incf timers) nil)))
      (should-not (glasspane-packages-maybe-auto-install))
      (should-not glasspane-packages--attempted)
      (should (zerop timers)))))

(ert-deftest glasspane-test-packages-install-defers ()
  "The D2 showcase: dispatch answers `accepted' with ZERO synchronous
ensure calls — the install runs only when the deferred continuation
fires, and the outcome toast rides it.  Mid-install (the re-entrancy
flag up) a second tap still answers without scheduling a second
install."
  (let ((handler (gethash "glasspane.packages.install"
                          jetpacs-action-handlers))
        (ensures 0) (continuations nil) (toasts nil))
    (should handler)
    (cl-letf (((symbol-function 'glasspane-packages-ensure)
               (lambda () (cl-incf ensures) t))
              ((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (push fn continuations)))
              ((symbol-function 'jetpacs-toast)
               (lambda (text &rest _) (push text toasts) nil)))
      (should (eq (funcall handler nil nil) 'accepted))
      (should (zerop ensures))
      (should (= (length continuations) 1))
      (funcall (car continuations))
      (should (= ensures 1))
      (should (cl-some (lambda (s) (string-search "ready" s)) toasts))
      (let ((glasspane-packages--installing t))
        (should (eq (funcall handler nil nil) 'accepted))
        (should (= (length continuations) 1))
        (should (= ensures 1))))))

(ert-deftest glasspane-test-packages-settings-registered ()
  "`glasspane-register' (run at the entry's load) registered the
Packages section: the auto-install row is present with a label, and
the symbol's boolean custom-type is what derives its switch."
  (let ((entries (alist-get "Packages" jetpacs-settings-registry
                            nil nil #'equal)))
    (should entries)
    (let ((entry (assq 'glasspane-packages-auto-install entries)))
      (should entry)
      (should (stringp (plist-get (cdr entry) :label)))))
  (should (eq (get 'glasspane-packages-auto-install 'custom-type)
              'boolean)))

;;;; G3 — keystone: glasspane-ui.el

(ert-deftest glasspane-test-ui-todo-sequences ()
  "The pure TODO-keyword helpers: the explicit-bar split, org's
last-keyword-is-finished rule for bar-less sequences, and the
fast-access-key strip in the flat global list."
  (require 'glasspane-ui)
  (should (equal (glasspane-ui--split-todo-sequence
                  '(sequence "TODO(t!)" "NEXT" "|" "DONE(d)"))
                 (cons '("TODO(t!)" "NEXT") '("DONE(d)"))))
  ;; No bar: the last keyword is the finished state.
  (should (equal (glasspane-ui--split-todo-sequence
                  '(sequence "TODO" "DONE"))
                 (cons '("TODO") '("DONE"))))
  ;; A single bar-less keyword IS the finished state.
  (should (equal (glasspane-ui--split-todo-sequence '(sequence "DONE"))
                 (cons nil '("DONE"))))
  ;; An explicit bar with nothing after it: nothing is finished.
  (should (equal (glasspane-ui--split-todo-sequence
                  '(sequence "TODO" "|"))
                 (cons '("TODO") nil)))
  ;; The flat global list strips fast keys, across sequence types.
  (let ((org-todo-keywords '((sequence "TODO(t)" "|" "DONE(d!)")
                             (type "BUG(b)" "FIXED"))))
    (should (equal (glasspane-ui--global-todo-keywords)
                   '("TODO" "DONE" "BUG" "FIXED")))))

(ert-deftest glasspane-test-ui-settings-nodes ()
  "Settings body shapes over stubbed org vars: tag options survive
group markers and duplicates (the enum's build-time distinctness
check), both enum sites build from enum-option nodes, and the body,
the Display render block, the satellite link, and the pushed screen
all round-trip the canonical wire encoding."
  (require 'glasspane-ui)
  (let ((org-tag-alist '(("home" . ?h) (:startgroup) "work" "home"))
        (glasspane-org-custom-agendas '(("Errands" . "tags:errand")))
        (org-todo-keywords '((sequence "TODO(t)" "|" "DONE")))
        (jetpacs-line-numbers 'relative))
    (should (equal (glasspane-ui--tag-options) '("home" "work")))
    (let ((json (jetpacs-node->canonical-json
                 (glasspane-ui--line-numbers-node))))
      (should (string-search "\"enum_list\"" json))
      (should (string-search "\"Relative\"" json))
      (should (string-search "settings.line-numbers" json)))
    (let* ((body (glasspane-ui--settings-body))
           (json (jetpacs-node->canonical-json body)))
      (should (equal (plist-get body :t) "lazy_column"))
      (should (string-search "Errands" json))
      (should (string-search "tags:errand" json))
      (should (string-search "settings.agenda.edit" json))
      (should (string-search "settings.agenda.delete" json))
      ;; The sequence card shows bare keywords, active | finished.
      (should (string-search "Sequence 1" json))
      (should (string-search "TODO | DONE" json))
      (should (string-search "settings.todo.edit" json))
      ;; The tags enum: chips seeded all-selected, additions allowed.
      (should (string-search "\"settings-tags\"" json))
      (should (string-search "\"allow_add\":true" json)))
    (let ((json (jetpacs-node->canonical-json
                 (glasspane-ui--settings-link))))
      (should (string-search "glasspane.settings.open" json)))
    (let ((screen (glasspane-ui--settings-screen nil)))
      (should (equal (plist-get screen :t) "scaffold"))
      (should (stringp (jetpacs-node->canonical-json screen))))))

(ert-deftest glasspane-test-ui-at-ref-classifier ()
  "The S4/S5 funnel every later rung copies: no/unknown token ->
\\='stale, `ebp-org-refused' -> \\='rejected, `ebp-org-unresolved' ->
\\='stale, success -> \\='accepted with the memo busted (namespaced
without save, the synchronous app funnel with), and a signal from the
mutation body never answers \\='accepted."
  (require 'glasspane-ui)
  (should (eq (glasspane-ui--at-ref nil #'ignore) 'stale))
  (should (eq (glasspane-ui--at-ref '(:token "o0-swept") #'ignore) 'stale))
  (let ((ref '(:id nil :file "/vault/tasks.org" :pos 1 :headline "H")))
    (cl-letf (((symbol-function 'ebp-org-token-ref)
               (lambda (&rest _) ref)))
      (cl-letf (((symbol-function 'ebp-org-resolve-ref)
                 (lambda (_) (signal 'ebp-org-refused nil))))
        (should (eq (glasspane-ui--at-ref '(:token "t") #'ignore)
                    'rejected)))
      (cl-letf (((symbol-function 'ebp-org-resolve-ref)
                 (lambda (_) (signal 'ebp-org-unresolved nil))))
        (should (eq (glasspane-ui--at-ref '(:token "t") #'ignore)
                    'stale)))
      (with-temp-buffer
        (org-mode)
        (insert "* Heading\n")
        (let ((m (copy-marker (point-min)))
              (at nil) (invalidated nil) (saved 0))
          (cl-letf (((symbol-function 'ebp-org-resolve-ref)
                     (lambda (_) (copy-marker m)))
                    ((symbol-function 'ebp-org-cache-invalidate)
                     (lambda (&optional ns) (push ns invalidated)))
                    ((symbol-function 'glasspane-org--save-and-invalidate)
                     (lambda (&optional _) (cl-incf saved))))
            (should (eq (glasspane-ui--at-ref
                         '(:token "t") (lambda () (setq at (point))))
                        'accepted))
            (should (equal at (point-min)))
            (should (equal invalidated '(glasspane)))
            (should (zerop saved))
            (should (eq (glasspane-ui--at-ref '(:token "t") #'ignore t)
                        'accepted))
            (should (= saved 1))
            (should (eq (glasspane-ui--at-ref
                         '(:token "t") (lambda () (error "boom")))
                        'rejected))))))))

(ert-deftest glasspane-test-ui-handler-statuses ()
  "Every G3 verb, funcalled straight from the handler table with plist
args and no client, answers a SPEC 14.4 status symbol — then the sharp
edges: persisted writes, the single-writer defvars, stale indices and
names, malformed args, and dialog verbs refusing without a client.
Registration is idempotent (one settings link) and the section is in
the registry."
  (require 'glasspane-ui)
  (glasspane-ui-register)
  (should (alist-get "Glasspane" jetpacs-settings-registry
                     nil nil #'equal))
  (glasspane-ui-register)
  (should (= 1 (cl-count #'glasspane-ui--settings-link
                         jetpacs-settings-links :key #'cadr)))
  (let ((glasspane-org-custom-agendas '(("Errands" . "tags:errand")
                                        ("Old" . "todo:TODO")))
        (glasspane-ui-agenda-anchor "2020-01-01")
        (glasspane-ui-agenda-selected-date "2020-01-02")
        (glasspane-ui--files-filter "old")
        (glasspane-ui--settings-dialog nil)
        (jetpacs-line-numbers nil)
        (org-tag-alist '(("home" . ?h)))
        (org-todo-keywords '((sequence "TODO" "|" "DONE")))
        (saved nil) (continuations nil))
    (cl-letf (((symbol-function 'jetpacs-settings-save-variable)
               (lambda (sym val) (push (cons sym val) saved) val))
              ((symbol-function 'jetpacs-shell-notify)
               (lambda (&rest _) nil))
              ((symbol-function 'jetpacs-toast) (lambda (&rest _) nil))
              ((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (push fn continuations) nil)))
      (cl-flet ((run (name args &optional params)
                  (let ((handler (gethash name jetpacs-action-handlers)))
                    (should handler)
                    (funcall handler args params))))
        ;; The whole table answers statuses on bare nil/nil input.
        (dolist (name glasspane-ui--verbs)
          (should (memq (run name nil nil) '(accepted stale rejected))))
        ;; settings.line-numbers: one option value or nil, persisted.
        (should (eq (run "settings.line-numbers" '(:value "Relative"))
                    'accepted))
        (should (eq (cdr (assq 'jetpacs-line-numbers saved)) 'relative))
        (should (eq (run "settings.line-numbers" '(:value 5)) 'rejected))
        ;; settings.tags: vector rebuilds keeping fast-select conses;
        ;; wrong shapes reject.
        (should (eq (run "settings.tags" '(:value ["work" "home"]))
                    'accepted))
        (should (equal org-tag-alist '("work" ("home" . ?h))))
        (should (assq 'org-tag-alist saved))
        ;; Deselecting every chip is a well-formed no-op: accepted,
        ;; nothing written, alist untouched (the chips re-seed from it).
        (setq saved (assq-delete-all 'org-tag-alist saved))
        (should (eq (run "settings.tags" '(:value [])) 'accepted))
        (should-not (assq 'org-tag-alist saved))
        (should (equal org-tag-alist '("work" ("home" . ?h))))
        (should (eq (run "settings.tags" '(:value 42)) 'rejected))
        (should (eq (run "settings.tags" '(:value ["x" 5])) 'rejected))
        ;; settings.todo.edit: float index coerces; a vanished index is
        ;; stale; a well-formed tap without a client cannot present.
        (should (eq (run "settings.todo.edit" '(:index 99)) 'stale))
        (should (eq (run "settings.todo.edit" '(:index "x")) 'rejected))
        (should (eq (run "settings.todo.edit" '(:index 0)) 'rejected))
        (should (eq (run "settings.todo.edit" '(:index -1.0)) 'rejected))
        ;; settings.agenda.edit: dialog verb — same no-client refusal.
        (should (eq (run "settings.agenda.edit" '(:name 42)) 'rejected))
        (should (eq (run "settings.agenda.edit" '(:name "Errands"))
                    'rejected))
        ;; settings.agenda.delete: gone name is stale, present deletes.
        (should (eq (run "settings.agenda.delete" '(:name "Ghost"))
                    'stale))
        (should (eq (run "settings.agenda.delete" '(:name "Errands"))
                    'accepted))
        (should-not (assoc "Errands" glasspane-org-custom-agendas))
        ;; settings.agenda.save: captured fields ride params; a rename
        ;; drops the old row; an empty name rejects.
        (should (eq (run "settings.agenda.save" '(:old-name "Old")
                         '(:fields (:agenda-name " New "
                                    :agenda-query "todo:TODO")))
                    'accepted))
        (should (equal (assoc "New" glasspane-org-custom-agendas)
                       '("New" . "todo:TODO")))
        (should-not (assoc "Old" glasspane-org-custom-agendas))
        (should (eq (run "settings.agenda.save" nil
                         '(:fields (:agenda-name "  ")))
                    'rejected))
        ;; agenda.save-custom: no client, no dialog — never a hang.
        (should (eq (run "agenda.save-custom" '(:query "todo:TODO"))
                    'rejected))
        (should (eq (run "agenda.save-custom" '(:query 5)) 'rejected))
        ;; The S2 defvars: handlers are the single writer.
        (should (eq (run "agenda.set-month" '(:value "2026-08"))
                    'accepted))
        (should (equal glasspane-ui-agenda-anchor "2026-08-01"))
        (should (eq (run "agenda.set-month" '(:value "junk")) 'rejected))
        (should (eq (run "agenda.select-date" '(:value "2026-08-13"))
                    'accepted))
        (should (equal glasspane-ui-agenda-selected-date "2026-08-13"))
        (should (eq (run "agenda.select-date" '(:date "2026-08-14"))
                    'accepted))
        (should (equal glasspane-ui-agenda-selected-date "2026-08-14"))
        (should (eq (run "agenda.select-date" '(:value "13-08-2026"))
                    'rejected))
        (should (eq (run "agenda.today" nil) 'accepted))
        (should-not glasspane-ui-agenda-anchor)
        (should-not glasspane-ui-agenda-selected-date)
        (should (eq (run "files.filter" '(:value "tags:home"))
                    'accepted))
        (should (equal glasspane-ui--files-filter "tags:home"))
        (should (eq (run "files.filter" nil) 'rejected))
        ;; glasspane.settings.open: accepted on the strength of the
        ;; deferred push — zero pushes inside the dispatch extent.
        (let ((before (length continuations)))
          (should (eq (run "glasspane.settings.open" nil
                           '(:surface "app:jetpacs.settings"))
                      'accepted))
          (should (= (length continuations) (1+ before))))))))

(provide 'glasspane-test)
;;; glasspane-test.el ends here
