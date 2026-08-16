;;; glasspane-test.el --- Glasspane app ladder gates -*- lexical-binding: t; -*-

;; The per-rung LOCAL GATE suite of docs/PLAN-glasspane-app.md: every
;; rung adds its NAMED assertions here, and test/run-tests.sh runs the
;; whole file after the M3 stanza.  G0's three gates pin registration,
;; home serialization, and unload hygiene.

;;; Code:

(require 'ert)
(require 'jetpacs-org-mode)
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
  "The REGISTERED root screen builds and round-trips the canonical wire
encoding — the same bar every later rung's screens must clear.  The
builder is glasspane-ui's hub since the #26 rung; the G0 contract is
unchanged, and deliberately names the same function
`glasspane-register' does: whatever the chrome root points at must
build offline and serialize."
  (let ((screen (glasspane-ui-home-screen nil)))
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
  "Unregistration leaves no downstream verb, claim, or registry entry.
Sibling modules register through `glasspane-register', while the native Org
clock owner must survive.  Re-registration restores the app so suite order
never matters."
  (let ((verbs '("glasspane.home"
                 "config.sync" "glasspane.packages.install"))
        (native-clock-verbs
         '("org.clock.out" "org.clock.switch" "org.clock.in-last")))
    ;; GR-5: the clock machinery is upstream and must survive a downstream
    ;; app unregister just as the foundation's Org settings do.
    (dolist (name native-clock-verbs)
      (should (eq (gethash name jetpacs-action-handlers)
                  (pcase name
                    ("org.clock.out" #'jetpacs-org-clock--on-out)
                    ("org.clock.switch" #'jetpacs-org-clock--on-switch)
                    (_ #'jetpacs-org-clock--on-in-last))))
      (should (equal (jetpacs--owner-of "action" name) "org-mode")))
    (unwind-protect
        (progn
          (glasspane-unregister)
          (dolist (name verbs)
            (should-not (gethash name jetpacs-action-handlers))
            ;; The claim record goes with the handler: teardown-owner
            ;; and unregister must agree on what "glasspane" owns.
            (should-not (jetpacs--owner-of "action" name)))
          (should-not (assoc glasspane-owner jetpacs-apps--registry))
          (dolist (name native-clock-verbs)
            (should (gethash name jetpacs-action-handlers))
            (should (equal (jetpacs--owner-of "action" name) "org-mode")))
          ;; §3 step 2: the app's ONE consolidated section sweeps with
          ;; it — and the foundation's org sections must SURVIVE the
          ;; app's unregister (they are not glasspane's to sweep).
          (should-not (alist-get "Glasspane" jetpacs-settings-registry
                                 nil nil #'equal))
          (should (alist-get "Org Workflow" jetpacs-settings-registry
                             nil nil #'equal)))
      (glasspane-register))
    (dolist (name verbs)
      (should (gethash name jetpacs-action-handlers))
      (should (equal (jetpacs--owner-of "action" name) glasspane-owner)))
    (should (alist-get "Glasspane" jetpacs-settings-registry
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

(ert-deftest glasspane-test-org-directory-agenda-scope ()
  "A DIRECTORY entry in `org-agenda-files' expands to the org files inside.
The managed config's default is `(list org-directory)`; org-agenda's
own machinery expands directory entries but `org-map-entries' visits
the raw dir as dired and answers nothing — on the G9 device the same
corpus filled Agenda and left Tasks empty.  The scope must hand every
consumer FILES."
  (let* ((vault (make-temp-file "glasspane-vault" t))
         (file (expand-file-name "tasks.org" vault))
         (org-directory vault)
         (org-agenda-files (list vault))
         (ebp-org-roots nil))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* TODO From the directory scope\n"
                    "* Not a task\n"))
          (ebp-org-cache-invalidate)
          (let ((scope (glasspane-org--agenda-scope)))
            (should (equal scope (list file)))
            (should-not (cl-find-if #'file-directory-p scope)))
          (let ((items (cl-letf (((symbol-function 'glasspane-org--vulpea-p)
                                  (lambda () nil)))
                         (glasspane-org--todo-items))))
            (should (= (length items) 1))
            (should (equal (alist-get 'headline (car items))
                           "From the directory scope"))))
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
                           "Water the garden")))
          ;; Cross-ARM probe: the memo key names the arm, so a vulpea
          ;; that lights up mid-session cannot be served the payload the
          ;; pre-vulpea sweep cached under the same scope.
          (let ((swept (cl-letf (((symbol-function 'glasspane-org--vulpea-p)
                                  (lambda () nil)))
                         (glasspane-org--todo-items))))
            (should (= (length swept) 2))
            (let ((indexed
                   (cl-letf (((symbol-function 'glasspane-org--vulpea-p)
                              (lambda () t))
                             ((symbol-function 'vulpea-db-query)
                              (lambda (&optional _pred) (list 'note)))
                             ((symbol-function 'glasspane-org--vulpea-note-to-item)
                              (lambda (_note) '((headline . "From the index")))))
                     (glasspane-org--todo-items))))
              (should-not (equal indexed swept))
              (should (equal (alist-get 'headline (car indexed))
                             "From the index"))))
          ;; The tag vocabulary rides the same rule: `--all-tags' keys
          ;; on its arm too, so the index's answer is not served from
          ;; the pre-vulpea sweep's entry under the same scope.
          (let ((swept (glasspane-org--all-tags)))
            (should (member "home" swept))
            (let ((indexed
                   ;; The arm's own probe is `featurep', which reads
                   ;; the GLOBAL `features' — a lexical `let' would not
                   ;; be seen from C.
                   (cl-letf (((symbol-value 'features)
                              (cons 'vulpea features))
                             ((symbol-function 'vulpea-db-query-tags)
                              (lambda () '("indexed"))))
                     (glasspane-org--all-tags))))
              (should-not (equal indexed swept))
              (should (member "indexed" indexed)))))
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
      ;; The docstring's LOAD clause, asserted: re-loading the file with
      ;; the hooks swept must leave every global org hook exactly as
      ;; `glasspane-org-remove-hooks' left it — a top-level `add-hook'
      ;; would attach here, where no app enable has run.
      (load "glasspane-org")
      (should-not (member #'glasspane-org--before-save-timestamps
                          before-save-hook))
      (should-not (member #'glasspane-org--heading-created-property
                          org-insert-heading-hook))
      (should-not (member #'glasspane-org--heading-modified-property
                          org-property-changed-functions))
      (should-not (member #'glasspane-org--todo-modified-property
                          org-after-todo-state-change-hook))
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

;;;; G2 / GR-5 — downstream clock rollback adapter

(ert-deftest glasspane-test-clock-rollback-adapter-is-inert-by-default ()
  "The downstream owner is opt-in and never removes native handlers by accident."
  (should-not (default-value 'glasspane-clock-enabled))
  (unwind-protect
      (progn
        (let ((jetpacs-org-clock-enabled t))
          (jetpacs-org-clock-register))
        ;; Normal forward state: registering the disabled downstream adapter
        ;; leaves the upstream owner and hooks byte-for-byte intact.
        (let ((glasspane-clock-enabled nil))
          (glasspane-clock-install-hooks))
        (should (eq (gethash "org.clock.out" jetpacs-action-handlers)
                    #'jetpacs-org-clock--on-out))
        (should (equal (jetpacs--owner-of "action" "org.clock.out")
                       "org-mode"))
        (should-not (memq #'glasspane-clock--assert org-clock-in-hook))

        ;; Rollback state: the downstream adapter first retires the upstream
        ;; integration, then owns the unchanged durable names itself.
        (let ((jetpacs-org-clock-enabled nil))
          (jetpacs-org-clock-register))
        (let ((glasspane-clock-enabled t))
          (glasspane-clock-install-hooks))
        (dolist (name '("org.clock.out" "org.clock.switch"
                        "org.clock.in-last"))
          (should (gethash name jetpacs--any-surface-actions))
          (should (equal (jetpacs--owner-of "action" name) "glasspane")))
        (should (eq (gethash "org.clock.out" jetpacs-action-handlers)
                    #'glasspane-clock--on-out))
        (should (memq #'glasspane-clock--assert org-clock-in-hook))
        (should-not (memq #'jetpacs-org-clock--assert org-clock-in-hook)))
    ;; Every exit restores the canonical owner for the remainder of the suite.
    (let ((glasspane-clock-enabled nil))
      (glasspane-clock-install-hooks))
    (let ((jetpacs-org-clock-enabled t))
      (jetpacs-org-clock-register))))

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
  ;; Derived properties, never a restatement of the constant: a
  ;; verbatim copy of `glasspane-packages--set' would pass under any
  ;; edit made in both places.  The floors are what the --outdated
  ;; probe feeds to `version-to-list', which SIGNALS on junk.
  (should (version-to-list (alist-get 'org-ql glasspane-packages--set)))
  (should (stringp (alist-get 'vulpea glasspane-packages--set)))
  (should (version-to-list (alist-get 'vulpea glasspane-packages--set)))
  ;; One entry per package: `alist-get' would silently read the first.
  (should (= (length (delete-dups (mapcar #'car glasspane-packages--set)))
             (length glasspane-packages--set)))
  (cl-letf (((symbol-function 'sqlite-available-p) (lambda () nil)))
    (should-not (assq 'vulpea (glasspane-packages--wanted)))
    (should (equal (mapcar #'car (glasspane-packages--wanted))
                   '(org-ql org-srs ef-themes))))
  (cl-letf (((symbol-function 'sqlite-available-p) (lambda () t)))
    (should (equal (glasspane-packages--wanted) glasspane-packages--set)))
  ;; --outdated is the FLOOR probe over package.el's own installs, and
  ;; it is DISJOINT from --missing, which only asks whether a package
  ;; loads: an old-but-loadable engine is outdated and never missing.
  (cl-letf (((symbol-function 'sqlite-available-p) (lambda () t))
            ((symbol-function 'package-installed-p)
             (lambda (pkg &optional min) (and (eq pkg 'vulpea) (null min)))))
    (should (equal (glasspane-packages--outdated) '(vulpea)))
    ;; The same stub cannot move --missing: it probes `require', and
    ;; every engine is absent from this harness.
    (should (equal (glasspane-packages--missing)
                   (mapcar #'car glasspane-packages--set))))
  ;; A floorless entry never appears, not even fully installed — there
  ;; is no version for it to be below.
  (cl-letf (((symbol-function 'sqlite-available-p) (lambda () t))
            ((symbol-function 'package-installed-p)
             (lambda (pkg &optional _min) (eq pkg 'org-srs))))
    (should-not (glasspane-packages--outdated))))

(ert-deftest glasspane-test-packages-ensure-floor-installs ()
  "Both sets gate the install branch: with NOTHING missing but a
below-floor engine outstanding, ensure must reach package.el instead of
short-circuiting to the light-up — an old-but-loadable vulpea leaves
`--missing' empty, so a missing-only gate could never raise the floor.
The floor case installs the archive DESC, since `package-install' given
a bare symbol no-ops for any installed version."
  ;; package.el's own defvars must exist BEFORE the let below, or the
  ;; bindings would be lexical ones the branch never sees.
  (require 'package)
  (let ((glasspane-packages--installing nil)
        (refreshes 0) (installed nil) (lit 0)
        ;; The real store is off limits in the harness: a live
        ;; `package-initialize' would scan the user's elpa directory,
        ;; and the archive list is global state.
        (package--initialized t)
        (package-archives nil)
        (package-archive-contents '((vulpea vulpea-desc))))
    (cl-letf (((symbol-function 'glasspane-packages--missing) (lambda () nil))
              ((symbol-function 'glasspane-packages--outdated)
               (lambda () '(vulpea)))
              ((symbol-function 'package-refresh-contents)
               (lambda (&rest _) (cl-incf refreshes)))
              ((symbol-function 'package-install)
               (lambda (pkg &rest _) (push pkg installed)))
              ((symbol-function 'glasspane-packages--light-up)
               (lambda () (cl-incf lit))))
      (should (glasspane-packages-ensure))
      (should (= refreshes 1))
      (should (equal installed '(vulpea-desc)))
      ;; The light-up still runs — at the END of the install branch,
      ;; not as the short circuit that skipped it.
      (should (= lit 1))
      (should-not glasspane-packages--installing))))

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
  "The auto-install row lives in the CONSOLIDATED \"Glasspane\"
section (§3 step 2): glasspane-packages registers no section of its
own anymore, the row is present with a label under the app block, and
the symbol's boolean custom-type is what derives its switch."
  (should-not (alist-get "Packages" jetpacs-settings-registry
                         nil nil #'equal))
  (let ((entries (alist-get "Glasspane" jetpacs-settings-registry
                            nil nil #'equal)))
    (should entries)
    (let ((entry (assq 'glasspane-packages-auto-install entries)))
      (should entry)
      (should (stringp (plist-get (cdr entry) :label)))))
  (should (eq (get 'glasspane-packages-auto-install 'custom-type)
              'boolean)))

;;;; G3 — keystone: glasspane-ui.el

(ert-deftest glasspane-test-ui-settings-nodes ()
  "Settings body shapes: the app screen is the saved searches ALONE
after §3 step 2 (the TODO/tags editors are the foundation's Org
workflow satellite now — jetpacs-org-settings-test.el owns them), and
the body, the satellite link, and the pushed screen all round-trip
the canonical wire encoding."
  (require 'glasspane-ui)
  (let ((glasspane-org-custom-agendas '(("Errands" . "tags:errand"))))
    (let* ((body (glasspane-ui--settings-body))
           (json (jetpacs-node->canonical-json body)))
      (should (equal (plist-get body :t) "lazy_column"))
      (should (string-search "Errands" json))
      (should (string-search "tags:errand" json))
      (should (string-search "settings.agenda.edit" json))
      (should (string-search "settings.agenda.delete" json))
      ;; The moved editors must NOT resurface here.
      (should-not (string-search "Sequence 1" json))
      (should-not (string-search "settings.todo" json))
      (should-not (string-search "org-tags" json)))
    (let ((json (jetpacs-node->canonical-json
                 (glasspane-ui--settings-link))))
      (should (string-search "glasspane.settings.open" json))
      (should (string-search "Saved searches" json)))
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
  (unwind-protect
      (progn
	;; The app section is the §3 step-2 CONSOLIDATION: babel timeout,
	;; journal landing, and packages auto-install in ONE "Glasspane"
	;; block — one registration site (here), three sibling defcustoms,
	;; all plain (none feeds a memoised extraction).
	(let ((entries (alist-get "Glasspane" jetpacs-settings-registry
				  nil nil #'equal)))
	  (should entries)
	  (dolist (sym '(glasspane-babel-timeout
			 glasspane-journal-landing
			 glasspane-packages-auto-install))
	    (should (assq sym entries))
	    (should-not (plist-get (cdr (assq sym entries)) :after-set))))
	(glasspane-ui-register)
	(should (= 1 (cl-count #'glasspane-ui--settings-link
                               jetpacs-settings-links :key #'cadr)))
	(let ((glasspane-org-custom-agendas '(("Errands" . "tags:errand")
                                              ("Old" . "todo:TODO")))
              (glasspane-ui-agenda-anchor "2020-01-01")
              (glasspane-ui-agenda-selected-date "2020-01-02")
              (jetpacs-settings--dialog nil)
              (org-tag-alist '(("home" . ?h)))
              (org-todo-keywords '((sequence "TODO" "|" "DONE")))
              (saved nil) (continuations nil) (pushes 0))
	  (cl-letf (((symbol-function 'jetpacs-settings-save-variable)
		     (lambda (sym val) (push (cons sym val) saved) val))
		    ((symbol-function 'jetpacs-shell-notify)
		     (lambda (&rest _) nil))
		    ((symbol-function 'jetpacs-toast) (lambda (&rest _) nil))
		    ;; Counted, not merely absorbed: with no root defined a
		    ;; direct push silently no-ops, so nothing else here
		    ;; could tell a D2 violation from the deferred path.
		    ((symbol-function 'jetpacs-shell-push)
		     (lambda (&rest _) (cl-incf pushes) nil))
		    ((symbol-function 'jetpacs-flow-continue)
		     (lambda (fn) (push fn continuations) nil)))
	    (cl-flet ((run (name args &optional params)
			(let ((handler (gethash name jetpacs-action-handlers)))
			  (should handler)
			  (funcall handler args params))))
              ;; The whole table answers statuses on bare nil/nil input.
              (dolist (name glasspane-ui--verbs)
		(should (memq (run name nil nil) '(accepted stale rejected))))
              ;; (The settings.tags / settings.todo.* arms left with §3
              ;; step 2 — jetpacs-org-settings-test.el covers the
              ;; foundation's jetpacs.org.* family now.)
              ;; settings.agenda.edit: dialog verb — no-client refusal.
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
              ;; glasspane.settings.open: accepted on the strength of the
              ;; deferred push — zero pushes inside the dispatch extent.
              (let ((before (length continuations)))
		(should (eq (run "glasspane.settings.open" nil
				 '(:surface "app:jetpacs.settings"))
			    'accepted))
		(should (= (length continuations) (1+ before))))
              ;; D2 across the WHOLE table: every legitimate push in this
              ;; file lives inside a continuation the stub never runs, so
              ;; nothing above may have pushed inside a dispatch extent.
              (should (zerop pushes))
              ;; (The one-live-dialog slot is the foundation's now —
              ;; jetpacs-settings-test.el owns its single-writer and
              ;; identity-guard coverage.)
              ))))
    ;; The unregister sweep — its own gate, and the teardown this
    ;; batch process would otherwise carry into every later test: the
    ;; org-clock hooks, the teardown hook, and the Settings link.
    (glasspane-ui-unregister)
    (should-not (cl-find #'glasspane-ui--settings-link
                         jetpacs-settings-links :key #'cadr))
    ;; Re-registered so suite order never matters (the journal/srs
    ;; precedent).
    (glasspane-ui-register)))

;;;; G4 — reader: glasspane-org-reader.el

(defun glasspane-test--reader-vault ()
  "A throwaway vault with the reader fixture; (VAULT . FILE)."
  (let* ((vault (make-temp-file "glasspane-vault" t))
         (file (expand-file-name "reader.org" vault)))
    (with-temp-file file
      (insert "#+TITLE: Reader\n\n"
              "* TODO Water the garden :home:\n"
              "DEADLINE: <2020-01-02 Thu>\n"
              ":PROPERTIES:\n:EFFORT: 0:30\n:END:\n"
              "Remember the roses.\n"
              "** DONE Buy a hose\n"
              "Coiled, 20m.\n"
              "* Reference notes\n"
              "Plain body.\n"))
    (cons vault file)))

(defun glasspane-test--reader-cleanup (vault)
  "Kill the vault's buffers, sweep the reader mints, drop the vault."
  (ebp-org-cache-invalidate)
  (dolist (set '("reader-file" "reader-subtree"))
    (ebp-org-ref-tokens nil :set set :owner "glasspane")
    (ebp-org-ref-tokens nil :set (concat "glasspane-" set)
                        :owner jetpacs-org-dialogs-owner))
  (dolist (buf (buffer-list))
    (let ((f (buffer-file-name buf)))
      (when (and f (string-prefix-p (file-name-as-directory
                                     (file-truename vault))
                                    (file-truename f)))
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf))))
  (delete-directory vault t))

(defun glasspane-test--reader-ids (node)
  "Every :id in NODE's tree, depth first."
  (when (jetpacs-node-p node)
    (append (when (plist-get node :id) (list (plist-get node :id)))
            (cl-loop for (_k v) on node by #'cddr
                     append (cond
                             ((jetpacs-node-p v)
                              (glasspane-test--reader-ids v))
                             ((or (vectorp v) (proper-list-p v))
                              (cl-loop for x across (vconcat v)
                                       append (glasspane-test--reader-ids x))))))))

(ert-deftest glasspane-test-reader-registration-replaces-and-restores-org ()
  "Glasspane replaces only adapter `org'; unregister restores foundation."
  (require 'glasspane-org-reader)
  (glasspane-org-reader-register)
  (let ((adapter (jetpacs-reader-adapter-for "/tmp/reader.org")))
    (should (eq (jetpacs-reader-adapter-id adapter) 'org))
    (should (eq (jetpacs-reader-adapter-render adapter)
                #'glasspane-org-reader--adapter-render))
    (should (eq (jetpacs-reader-adapter-actions adapter)
                #'glasspane-org-reader--adapter-actions))
    (should (eq (jetpacs-reader-adapter-transition adapter)
                #'glasspane-org-reader--adapter-transition)))
  ;; The reusable reader/editor hosts are the only Files claimants; no
  ;; Glasspane body/actions function competes in the hook chain.
  (should (= 1 (cl-count #'jetpacs-reader--files-body
                         jetpacs-files-editor-body-functions)))
  (should (= 1 (cl-count #'jetpacs-reader--files-actions
                         jetpacs-files-editor-actions-functions)))
  (should-not (memq 'glasspane-org-reader--files-body
                    jetpacs-files-editor-body-functions))
  (should-not (memq 'glasspane-org-reader--files-actions
                    jetpacs-files-editor-actions-functions))
  (unwind-protect
      (progn
        (glasspane-org-reader-unregister)
        (let ((adapter (jetpacs-reader-adapter-for "/tmp/reader.org")))
          (should (eq (jetpacs-reader-adapter-render adapter)
                      #'jetpacs-reader-org--render))
          (should (eq (jetpacs-reader-adapter-actions adapter)
                      #'jetpacs-reader-org--actions))
          (should (eq (jetpacs-reader-adapter-transition adapter)
                      #'jetpacs-reader-org--transition)))
        (should-not (gethash "files.filter" jetpacs-action-handlers)))
    (glasspane-org-reader-register))
  (should (gethash "files.filter" jetpacs-action-handlers)))

(ert-deftest glasspane-test-reader-adapter-gate ()
  "GR-2 actions, fallback and rendered/plain round trip are lossless."
  (let* ((fixture (glasspane-test--reader-vault))
         (vault (car fixture))
         (file (cdr fixture))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots nil)
         (jetpacs-reader--state (make-hash-table :test #'equal))
         (jetpacs-files--edit (list :path (file-truename file))))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-max))
            (insert "* Secret :crypt:\n"
                    "-----BEGIN PGP MESSAGE-----\n"
                    "ciphertext\n"
                    "-----END PGP MESSAGE-----\n")
            (write-region (point-min) (point-max) file nil 'silent))
          (glasspane-org-reader-register)
          (jetpacs-reader-state-set file :gp-filter-query "todo:TODO")
          (let* ((before (glasspane-org-reader--adapter-render file))
                 (ids-before (glasspane-test--reader-ids before))
                 (actions (jetpacs-reader--files-actions file))
                 (json (jetpacs-node->canonical-json
                        (apply #'jetpacs-row actions))))
            ;; Host toggle + Glasspane refile + absorbed decrypt, and no
            ;; other stock Org action icons in the tree presentation.
            (should (string-search "jetpacs.reader.toggle" json))
            (should (string-search "files.toggle-refile" json))
            (should (string-search "jetpacs.reader.org.decrypt" json))
            (should-not (string-search "jetpacs.reader.org.reader-mode" json))
            (should-not (string-search "jetpacs.reader.org.visibility" json))
            (should-not (string-search "jetpacs.reader.org.search-toggle" json))
            ;; The generic host owns the transition.  Returning to reader
            ;; yields the same node ids, which is the Companion's key for
            ;; retaining device-local collapsible state.
            (cl-letf (((symbol-function 'jetpacs-buffer-defer-refresh)
                       #'ignore))
              (should (eq (jetpacs-reader--toggle
                           (list :path file) '(:surface "app:files"))
                          'accepted))
              (should (eq (jetpacs-reader-state-get file :presentation)
                          'editor))
              (should (eq (jetpacs-reader--toggle
                           (list :path file) '(:surface "app:files"))
                          'accepted))
              (should (eq (jetpacs-reader-state-get file :presentation)
                          'reader)))
            (let ((ids-after
                   (glasspane-test--reader-ids
                    (glasspane-org-reader--adapter-render file))))
              (should ids-before)
              (should (equal ids-after ids-before))
              (should (equal (glasspane-org-reader--filter-query file)
                             "todo:TODO"))))
          ;; A tree-builder signal degrades through the stock render callback,
          ;; rather than escaping to the host's generic Reader failed card.
          (jetpacs-reader-state-set file :gp-fold-mode 'tree)
          (cl-letf (((symbol-function 'glasspane-org-reader--reader-body)
                     (lambda (_path) (error "GR-2 injected render fault")))
                    ((symbol-function 'jetpacs-reader-org--render)
                     (lambda (_path) (jetpacs-text "Stock Org fallback"))))
            (let ((json (jetpacs-node->canonical-json
                         (glasspane-org-reader--adapter-render file))))
              (should (string-search "Stock Org fallback" json))))
          ;; Teardown restores the stock adapter's complete action set.
          (glasspane-org-reader-unregister)
          (let ((json (jetpacs-node->canonical-json
                       (apply #'jetpacs-row
                              (jetpacs-reader--files-actions file)))))
            (should (string-search "jetpacs.reader.org.reader-mode" json))
            (should (string-search "jetpacs.reader.org.visibility" json))
            (should (string-search "jetpacs.reader.org.search-toggle" json))
            (should (string-search "jetpacs.reader.org.decrypt" json))
            (should-not (string-search "files.toggle-refile" json))))
      (glasspane-org-reader-register)
      (glasspane-test--reader-cleanup vault))))

(ert-deftest glasspane-test-reader-trees ()
  "File, subtree and refile trees over a temp fixture: canonical
serialization, the §16.2 app profile, §16.1 id uniqueness (the m3 gate
pattern) — plus the registered adapter: reader, refile drag list,
host-owned per-path state, stock fallback, and sparse filtering without
signalling out of the builder."
  (require 'glasspane-org-reader)
  (glasspane-org-reader-register)
  (let* ((fixture (glasspane-test--reader-vault))
         (vault (car fixture))
         (file (cdr fixture))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots nil))
    (unwind-protect
        (progn
          (ebp-org-cache-invalidate)
          ;; The whole-file tree: two foldable top levels.
          (let ((nodes (glasspane-org-reader-file file)))
            (should (= (length nodes) 2))
            (dolist (n nodes)
              (should (equal (plist-get n :t) "collapsible"))
              (should (progn (jetpacs-check-profile n 'app) t))
              (should (stringp (jetpacs-node->canonical-json n))))
            ;; §16.1: every id in the render is unique.
            (let ((ids (apply #'append
                              (mapcar #'glasspane-test--reader-ids nodes))))
              (should ids)
              (should (equal (length ids)
                             (length (cl-remove-duplicates
                                      ids :test #'equal)))))
            (let ((json (jetpacs-node->canonical-json
                         (apply #'jetpacs-column nodes))))
              ;; Long-press drills in on a minted token, never a ref.
              (should (string-search "heading.tap" json))
              (should (string-search "\"token\"" json))
              (should-not (string-search "\"file\":" json))
              ;; Swipes: todo cycle one side, the BASE archive (with
              ;; the descriptor-level confirm) the other.
              (should (string-search "heading.todo-cycle" json))
              (should (string-search "jetpacs.org.archive" json))
              (should (string-search "Archive this subtree?" json))
              ;; The menu delegates the retired editors to the base
              ;; sheet via the exposure route.
              (should (string-search "jetpacs.org.heading" json))
              ;; Overdue deadline badge, collapsed PROPERTIES drawer.
              (should (string-search "Deadline 2020-01-02" json))
              (should (string-search "PROPERTIES" json))
              (should (string-search "\"collapsed\":true" json))
              ;; Bodies degrade to org-syntax text (gap #6).
              (should (string-search "Remember the roses." json))
              (should (string-search "\"syntax\":\"org\"" json))
              ;; Done title: color degrade, never :strike (gap #7).
              (should (string-search "on_surface_variant" json))
              (should-not (string-search "strike" json))
              ;; Tag chips ride search.by-tag.
              (should (string-search "search.by-tag" json)))
            ;; The exposure route recorded each rendered heading for
            ;; the base sheet verb.
            (with-current-buffer (find-file-noselect file)
              (org-with-wide-buffer
               (goto-char (point-min))
               (re-search-forward "^\\* TODO Water")
               (should (jetpacs-buffer-exposed-p
                        (buffer-name) (line-beginning-position)
                        "jetpacs.org.heading")))))
          ;; The subtree: the drilled heading's body inline, the child
          ;; foldable; skip-props suppresses the drawer.
          (let ((pos (with-current-buffer (find-file-noselect file)
                       (org-with-wide-buffer
                        (goto-char (point-min))
                        (re-search-forward "^\\* TODO Water")
                        (line-beginning-position)))))
            (let* ((nodes (glasspane-org-reader-subtree file pos))
                   (json (jetpacs-node->canonical-json
                          (apply #'jetpacs-column nodes))))
              (should nodes)
              (should (string-search "Remember the roses." json))
              (should (string-search "Buy a hose" json))
              (should (string-search ":EFFORT: 0:30" json)))
            (let ((json (jetpacs-node->canonical-json
                         (apply #'jetpacs-column
                                (glasspane-org-reader-subtree file pos t)))))
              (should-not (string-search ":EFFORT: 0:30" json))))
          ;; The refile list: one reorderable node, every item keyed,
          ;; and the reorder action carrying the LIST id — file and
          ;; positions resolve Emacs-side (D-4).
          (let ((node (glasspane-org-reader-refile-list file)))
            (should (equal (plist-get node :t) "reorderable_list"))
            (should (progn (jetpacs-check-profile node 'app) t))
            (should (= (length (plist-get node :items)) 3))
            (let ((keys (mapcar (lambda (it) (plist-get it :key))
                                (append (plist-get node :items) nil))))
              (should (cl-every #'jetpacs-identifier-p keys))
              (should (equal (length keys)
                             (length (cl-remove-duplicates
                                      keys :test #'equal))))
              (let* ((args (plist-get (plist-get node :on_reorder) :args))
                     (record (glasspane-org-reader-refile-lookup
                              (plist-get args :list))))
                (should record)
                (should-not (plist-get args :file))
                (should (equal (plist-get record :file)
                               (file-truename file)))
                (should (equal (mapcar #'car (plist-get record :keys))
                               keys))
                (should (cl-every (lambda (kv) (integerp (cdr kv)))
                                  (plist-get record :keys))))))
          ;; Adapter surfacing: all state is host-owned and path-keyed;
          ;; filtering and refile mode cannot bleed into a sibling file.
          (let ((jetpacs-reader--state (make-hash-table :test #'equal)))
            (let ((body (jetpacs-reader--files-body file)))
              (should (equal (plist-get body :t) "lazy_column"))
              (let ((json (jetpacs-node->canonical-json body)))
                (should (string-search "files-filter" json))
                (should (string-search "Water the garden" json))))
            (jetpacs-reader-state-set file :gp-filter-query "todo:TODO")
            (let ((sibling (expand-file-name "sibling.org" vault)))
              (should (equal (glasspane-org-reader--filter-query sibling) ""))
              (should (eq (glasspane-org-reader--fold-mode sibling) 'tree)))
            (let ((json (jetpacs-node->canonical-json
                         (jetpacs-reader--files-body file))))
              (should (string-search "1 of 2 headings" json))
              (should (string-search "Water the garden" json))
              (should-not (string-search "Reference notes" json))
              (should (= (jetpacs-reader-state-get file :gp-filter-kept) 1))
              (should (= (jetpacs-reader-state-get file :gp-filter-total) 2)))
            (jetpacs-reader-state-set file :gp-filter-query "(todo")
            (let ((body (jetpacs-reader--files-body file)))
              (should body)
              (should-not (string-search
                           "collapsible"
                           (jetpacs-node->canonical-json body)))
              (should-not
               (jetpacs-reader-state-get file :gp-filter-kept 'missing)))
            (jetpacs-reader-state-set file :gp-filter-query "")
            (jetpacs-reader-state-set file :gp-fold-mode 'refile)
            (let* ((body (jetpacs-reader--files-body file))
                   (children (append (plist-get body :children) nil))
                   (list-node (cadr children)))
              ;; A reorderable list is itself vertically lazy.  Nesting it in
              ;; a lazy_column crashes Compose with infinite constraints; the
              ;; adapter must give it the finite remainder of a root column.
              (should (equal (plist-get body :t) "column"))
              (should (equal (plist-get list-node :t)
                             "reorderable_list"))
              (should (= (plist-get list-node :weight) 1)))
            (jetpacs-reader-state-set file :presentation 'editor)
            (should-not (jetpacs-reader--files-body file))
            ;; In editor mode the host keeps only its generic preview toggle;
            ;; adapter-specific refile/decrypt actions are reader-only.
            (should (= (length (jetpacs-reader--files-actions file)) 1)))
          ;; A non-org path is never claimed.  A Glasspane policy/render
          ;; refusal is caught inside the adapter and gets the stock reader.
          (should-not (jetpacs-reader-adapter-for "/tmp/x.txt"))
          (let ((outside (make-temp-file "glasspane-outside" nil ".org")))
            (unwind-protect
                (progn
                  (with-temp-file outside (insert "* TODO Elsewhere\n"))
                  (let* ((body (glasspane-org-reader--adapter-render outside))
                         (json (jetpacs-node->canonical-json body)))
                    (should (string-search "Elsewhere" json))
                    (should-not (string-search "collapsible" json))))
              (delete-file outside)))
          ;; Reader handlers validate the live document, then write only its
          ;; :gp-* state cells.
          (let ((filter (gethash "files.filter" jetpacs-action-handlers))
                (toggle (gethash "files.toggle-refile"
                                 jetpacs-action-handlers))
                (jetpacs-reader--state (make-hash-table :test #'equal))
                (jetpacs-files--edit (list :path (file-truename file)))
                refreshed)
            (should filter)
            (should toggle)
            ;; GR-2 renders these Glasspane-owned descriptors on the stable
            ;; Files host.  Exercise the real D1 gate, not just the handler:
            ;; owner scope here would make every device tap silently dead.
            (dolist (name '("heading.menu" "files.filter"
                            "files.toggle-refile" "heading.reorder"))
              (should (gethash name jetpacs--any-surface-actions)))
            (cl-letf (((symbol-function 'jetpacs-buffer-defer-refresh)
                       (lambda (surface) (push surface refreshed))))
              (should (eq (jetpacs--dispatch
                           nil
                           (list :action "files.filter"
                                 :surface "app:jetpacs.files"
                                 :args (list :path file
                                             :value "tags:home"))
                           filter)
                          'accepted))
              (should (equal (glasspane-org-reader--filter-query file)
                             "tags:home"))
              (should (eq (jetpacs--dispatch
                           nil
                           (list :action "files.toggle-refile"
                                 :surface "app:jetpacs.files"
                                 :args (list :path file))
                           toggle)
                          'accepted))
              (should (eq (glasspane-org-reader--fold-mode file) 'refile))
              (should (eq (funcall toggle '(:path "/tmp/other.org")
                                   '(:surface "s"))
                          'stale))
              (should (equal refreshed
                             '("app:jetpacs.files"
                               "app:jetpacs.files"))))))
      (glasspane-test--reader-cleanup vault))))

(ert-deftest glasspane-test-reader-token-mint ()
  "The offline mint/resolve round trip (:owner \"glasspane\"): a
rendered heading's token resolves back to its ref and marker, the
archive token lives in the base dialogs' scope and nowhere else, a
re-render sweeps the previous set (replace semantics — swept sheets
answer stale for free), and the heading.menu verb classifies on the
same table."
  (require 'glasspane-org-reader)
  (glasspane-org-reader-register)
  (let* ((fixture (glasspane-test--reader-vault))
         (vault (car fixture))
         (file (cdr fixture))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots nil))
    (unwind-protect
        (progn
          (ebp-org-cache-invalidate)
          (let* ((nodes (glasspane-org-reader-file file))
                 (node (car nodes))
                 (token (plist-get
                         (plist-get (plist-get node :on_long_tap) :args)
                         :token))
                 (archive (plist-get
                           (plist-get
                            (plist-get (plist-get node :swipe_end)
                                       :on_trigger)
                            :args)
                           :token)))
            (should (stringp token))
            (should (stringp archive))
            (should-not (equal token archive))
            ;; The tap token: the app's own scope, and only that scope.
            (let ((ref (ebp-org-token-ref token :owner "glasspane")))
              (should ref)
              (should (equal (plist-get ref :file) (file-truename file)))
              (should (integerp (plist-get ref :pos)))
              (should (equal (plist-get ref :headline) "Water the garden"))
              (should-not (ebp-org-token-ref token :owner "someone-else"))
              (let ((m (ebp-org-resolve-ref ref)))
                (unwind-protect
                    (with-current-buffer (marker-buffer m)
                      (should (equal (file-truename buffer-file-name)
                                     (file-truename file)))
                      (org-with-wide-buffer
                       (goto-char m)
                       (should (org-at-heading-p))
                       (should (equal (nth 4 (org-heading-components))
                                      "Water the garden"))))
                  (set-marker m nil))))
            ;; The archive token: minted INTO the base dialogs' owner
            ;; scope so `jetpacs.org.archive' can resolve it — and
            ;; invisible to the app scope.
            (should (ebp-org-token-ref archive
                                       :owner jetpacs-org-dialogs-owner))
            (should-not (ebp-org-token-ref archive :owner "glasspane"))
            ;; Replace-set: a re-render retires the old generation.
            (glasspane-org-reader-file file)
            (should-not (ebp-org-token-ref token :owner "glasspane"))
            (should-not (ebp-org-token-ref
                         archive :owner jetpacs-org-dialogs-owner))
            ;; heading.menu classifies on the same table: junk shape
            ;; rejects, a swept token is stale, and a live token with
            ;; no client (so no dialog grant) refuses.
            (let ((handler (gethash "heading.menu" jetpacs-action-handlers)))
              (should handler)
              (should (eq (funcall handler nil nil) 'rejected))
              (should (eq (funcall handler '(:token 5) nil) 'rejected))
              (should (eq (funcall handler (list :token token) nil) 'stale))
              (let* ((fresh (glasspane-org-reader-file file))
                     (live (plist-get
                            (plist-get (plist-get (car fresh) :on_long_tap)
                                       :args)
                            :token)))
                (should (eq (funcall handler (list :token live) nil)
                            'rejected))))))
      (glasspane-test--reader-cleanup vault))))

(ert-deftest glasspane-test-reader-reorder ()
  "heading.reorder consumes the D-4 record (the integration seam both
porters flagged): a device drop moves the whole subtree on disk before
`accepted' and retires the spent per-list record, a junk shape
rejects, and a swept or mismatched list answers `stale'."
  (require 'glasspane-org-reader)
  (glasspane-org-reader-register)
  (let* ((fixture (glasspane-test--reader-vault))
         (vault (car fixture))
         (file (cdr fixture))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots nil)
         (refreshed nil))
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-buffer-defer-refresh)
                   (lambda (surface) (push surface refreshed))))
          (ebp-org-cache-invalidate)
          (let* ((node (glasspane-org-reader-refile-list file))
                 (handler (gethash "heading.reorder" jetpacs-action-handlers))
                 (args (plist-get (plist-get node :on_reorder) :args))
                 (list-id (plist-get args :list))
                 (keys (mapcar #'car (plist-get
                                      (glasspane-org-reader-refile-lookup
                                       list-id)
                                      :keys))))
            (should handler)
            ;; Fixture rows: Water(1) > Buy a hose(2), Reference(1).
            ;; Drag "Reference notes" (index 2) to the top (index 0).
            (should (eq (funcall handler
                                 (list :list list-id :from 2 :to 0
                                       :order (vector (nth 2 keys)
                                                      (nth 0 keys)
                                                      (nth 1 keys)))
                                 '(:surface "s"))
                        'accepted))
            (should (equal refreshed '("s")))
            (with-temp-buffer
              (insert-file-contents file)
              (let ((s (buffer-string)))
                (should (string-search "* Reference notes" s))
                (should (string-search "* TODO Water" s))
                (should (< (string-search "* Reference notes" s)
                           (string-search "* TODO Water" s)))))
            ;; The spent record retired with the move; the same list id
            ;; now classifies stale, junk shape still rejects.
            (should-not (glasspane-org-reader-refile-lookup list-id))
            (should (eq (funcall handler nil nil) 'rejected))
            (should (eq (funcall handler
                                 (list :list list-id :from 2 :to 0
                                       :order (vconcat keys))
                                 nil)
                        'stale))))
      (glasspane-test--reader-cleanup vault))))

;;;; G4 — reader + detail: glasspane-detail.el

(ert-deftest glasspane-test-detail-builders ()
  "Golden node trees from fixture plists: the logbook renderer's three
arms, the property-row control matrix (including the link-beats-date
cond order v1 got backwards), the chip rails' clear-on-active args,
and the shared agenda/result cards — G5's pure formatters stubbed
until the agenda rung lands them — all round-tripping the canonical
wire encoding."
  (require 'glasspane-detail)
  ;; Logbook arms.
  (let* ((clock (glasspane-ui--render-logbook-entry
                 '(:type clock :active nil
                   :start "2026-08-10 Mon 10:00" :end "2026-08-10 Mon 11:30"
                   :duration "1:30")))
         (json (jetpacs-node->canonical-json clock)))
    (should (equal (plist-get clock :t) "row"))
    (should (string-search "2026-08-10, 10:00 to 11:30" json))
    (should (string-search "1:30" json)))
  (let ((json (jetpacs-node->canonical-json
               (glasspane-ui--render-logbook-entry
                '(:type note :timestamp "[2026-08-10 Mon]"
                  :content "call back")))))
    (should (string-search "Note" json))
    (should (string-search "call back" json)))
  (let ((json (jetpacs-node->canonical-json
               (glasspane-ui--render-logbook-entry
                '(:type state :from "TODO" :to "DONE"
                  :timestamp "[2026-08-10 Mon]" :content "")))))
    ;; Canonical JSON is UTF-8-encoded (unibyte): encode the arrow.
    (should (string-search (encode-coding-string "TODO → DONE" 'utf-8)
                           json)))
  ;; Property rows: ID read-only; boolean switch; allowed enum with the
  ;; single-select ONE-value rule; small number slider; link button
  ;; (must beat the bracketed-value date heuristic); free text input.
  (let ((json (jetpacs-node->canonical-json
               (glasspane-ui--property-row "ID" "abc-123" "tok" 7))))
    (should (string-search "abc-123" json))
    (should-not (string-search "text_input" json)))
  (let ((json (jetpacs-node->canonical-json
               (glasspane-ui--property-row "DONE?" "t" "tok" 7))))
    (should (string-search "\"switch\"" json))
    (should (string-search "\"checked\":true" json))
    (should (string-search "heading.prop-set" json)))
  (let ((json (jetpacs-node->canonical-json
               (glasspane-ui--property-row "STATUS" "open" "tok" 7
                                           '("open" "closed")))))
    (should (string-search "\"enum_list\"" json))
    (should (string-search "\"value\":\"open\"" json)))
  ;; A value the options no longer carry seeds NO selection rather
  ;; than failing the whole row at build time.
  (should (jetpacs-node->canonical-json
           (glasspane-ui--property-row "STATUS" "gone" "tok" 7
                                       '("open" "closed"))))
  (let ((json (jetpacs-node->canonical-json
               (glasspane-ui--property-row "EFFORT" "5" "tok" 7))))
    (should (string-search "\"slider\"" json)))
  (let ((json (jetpacs-node->canonical-json
               (glasspane-ui--property-row "CREATED" "[2026-08-10 Mon]"
                                           "tok" 7))))
    (should (string-search "\"date_button\"" json))
    (should (string-search "\"value\":\"2026-08-10\"" json)))
  (let ((json (jetpacs-node->canonical-json
               (glasspane-ui--property-row
                "LINK" "[[https://x.example][X]]" "tok" 7))))
    (should (string-search "org.link.open" json))
    (should (string-search "https://x.example" json))
    (should-not (string-search "date_button" json)))
  (let ((json (jetpacs-node->canonical-json
               (glasspane-ui--property-row "FOO" "bar" "tok" 7))))
    (should (string-search "\"text_input\"" json))
    (should (string-search "\"token\":\"tok\"" json))
    (should (string-search "\"name\":\"FOO\"" json)))
  ;; Chip rails: tapping the ACTIVE chip sends the clearing value.
  (let ((json (jetpacs-node->canonical-json
               (glasspane-ui--todo-chips "TODO" '("TODO" "DONE") "tok"))))
    (should (string-search "\"scroll\":true" json))
    (should (string-search "\"state\":\"\"" json))
    (should (string-search "\"state\":\"DONE\"" json))
    (should (string-search "\"selected\":true" json)))
  (let* ((org-priority-highest ?A)
         (org-priority-lowest ?B)
         (json (jetpacs-node->canonical-json
                (glasspane-ui--priority-chips "A" "tok"))))
    (should (string-search "\"value\":\"\"" json))
    (should (string-search "\"value\":\"B\"" json)))
  ;; The shared cards (G5 formatters stubbed until the agenda rung).
  (cl-letf (((symbol-function 'glasspane-ui--agenda-type-icon)
             (lambda (_type) '("schedule" . nil)))
            ((symbol-function 'glasspane-ui--agenda-type-label)
             (lambda (_type) "scheduled"))
            ((symbol-function 'glasspane-ui--card-date-row)
             (lambda (_it) nil)))
    (let* ((card (glasspane-detail--agenda-card
                  '((headline . "Water the garden") (todo . "DONE")
                    (type . "scheduled") (file . "/v/tasks.org")
                    (priority . "A") (tags . ["home"])
                    (token . "tok-1") (archive-token . "tok-arch"))))
           (json (jetpacs-node->canonical-json card)))
      (should (equal (plist-get card :t) "card"))
      (should (string-search "heading.tap" json))
      (should (string-search "\"token\":\"tok-1\"" json))
      (should (string-search "heading.menu" json))
      (should (string-search "heading.todo-cycle" json))
      (should (string-search "jetpacs.org.archive" json))
      (should (string-search "\"token\":\"tok-arch\"" json))
      (should (string-search "Archive this subtree?" json))
      ;; The done title takes the color degrade (gap #7), never strike.
      (should (string-search "on_surface_variant" json))
      (should-not (string-search "strike" json))
      (should (string-search "search.by-tag" json)))
    ;; No tokens -> a static card: no tap, no long-tap, no swipes.
    (let ((card (glasspane-detail--agenda-card '((headline . "Plain")))))
      (should-not (plist-get card :on_tap))
      (should-not (plist-get card :on_long_tap))
      (should-not (plist-get card :swipe_start))
      (should-not (plist-get card :swipe_end))))
  (let ((json (jetpacs-node->canonical-json
               (glasspane-ui--result-card
                '((headline . "Hit") (todo . "TODO") (file . "/v/a.org")
                  (tags . ["x"]) (token . "tok-2"))))))
    (should (string-search "heading.tap" json))
    (should (string-search "\"token\":\"tok-2\"" json))
    (should (string-search "search.by-tag" json))))

(ert-deftest glasspane-test-detail-handler-triples ()
  "Every detail verb answers a SPEC 14.4 status over temp org files,
org core only: the token gate (junk `stale', wrong shape `rejected'),
durable direct-arm mutations on disk before `accepted', bridged flows
scheduling continuations instead of prompting, dialog verbs refusing
without a client — and the pushed screen builds and serializes in
both modes, degrading to the go-back placeholder on a dead ref."
  (require 'glasspane-detail)
  (glasspane-detail-register)
  (let* ((vault (make-temp-file "glasspane-vault" t))
         (file (expand-file-name "tasks.org" vault))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots nil)
         (glasspane-ui--detail-read-mode t)
         (notified nil) (continuations nil) (pushes 0))
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &rest _) (push text notified)))
                  ((symbol-function 'jetpacs-toast) (lambda (&rest _) nil))
                  ((symbol-function 'jetpacs-shell-push)
                   (lambda (&rest _) (cl-incf pushes) nil))
                  ((symbol-function 'jetpacs-flow-continue)
                   (lambda (fn) (push fn continuations) nil)))
          (with-temp-file file
            (insert "#+TITLE: Tasks\n\n"
                    "* TODO Parent\n"
                    ":PROPERTIES:\n:FOO: bar\n:END:\n"
                    "body\n"
                    "** Child\n"
                    "* Second\n"))
          (ebp-org-cache-invalidate)
          (cl-flet* ((run (name args &optional params)
                       (let ((handler (gethash name jetpacs-action-handlers)))
                         (should handler)
                         (funcall handler args
                                  (or params '(:surface "app:glasspane")))))
                     (tok-for (headline)
                       (with-current-buffer (find-file-noselect file)
                         (org-with-wide-buffer
                          (goto-char (point-min))
                          (re-search-forward (regexp-quote headline))
                          (car (ebp-org-ref-tokens
                                (list (ebp-org-ref-at-point))
                                :set "t-detail" :owner "glasspane")))))
                     (file-text ()
                       (with-current-buffer (find-file-noselect file)
                         (buffer-substring-no-properties (point-min)
                                                         (point-max)))))
            ;; Registration is complete and idempotent.
            (dolist (name glasspane-detail--verbs)
              (should (gethash name jetpacs-action-handlers)))
            (glasspane-detail-register)
            (should (gethash "heading.tap" jetpacs-action-handlers))
            ;; The token gate every handler shares.
            (should (eq (run "heading.tap" '(:token 5)) 'rejected))
            (should (eq (run "heading.tap" '(:token "o0-swept")) 'stale))
            (should (eq (run "heading.tap" (list :token (tok-for "Parent")))
                        'accepted))
            (should (= (length continuations) 1))
            ;; todo-set: direct arm durable, clear arm, malformed, swept.
            (should (eq (run "heading.todo-set"
                             (list :state "DONE" :token (tok-for "Parent")))
                        'accepted))
            (should (string-search "* DONE Parent" (file-text)))
            (should (eq (run "heading.todo-set"
                             (list :state "" :token (tok-for "Parent")))
                        'accepted))
            (should-not (string-search "* DONE Parent" (file-text)))
            (should (eq (run "heading.todo-set" '(:state 5 :token "x"))
                        'rejected))
            (should (eq (run "heading.todo-set" '(:state "DONE")) 'stale))
            ;; todo-cycle steps the sequence.
            (should (eq (run "heading.todo-cycle"
                             (list :token (tok-for "Parent")))
                        'accepted))
            (should (string-search "* TODO Parent" (file-text)))
            ;; schedule: relative arm, clear arm, empty shape rejects.
            (should (eq (run "heading.schedule"
                             (list :when "+1d" :token (tok-for "Parent")))
                        'accepted))
            (should (string-search "SCHEDULED:" (file-text)))
            (should (eq (run "heading.schedule"
                             (list :clear t :token (tok-for "Parent")))
                        'accepted))
            (should-not (string-search "SCHEDULED:" (file-text)))
            (should (eq (run "heading.schedule"
                             (list :token (tok-for "Parent")))
                        'rejected))
            ;; priority: set, clear, malformed.
            (should (eq (run "heading.priority"
                             (list :value "A" :token (tok-for "Parent")))
                        'accepted))
            (should (string-search "[#A]" (file-text)))
            (should (eq (run "heading.priority"
                             (list :value "" :token (tok-for "Parent")))
                        'accepted))
            (should-not (string-search "[#A]" (file-text)))
            (should (eq (run "heading.priority" '(:value nil :token "x"))
                        'rejected))
            ;; tags: vector sets; a 23.1 charset violation and a bare
            ;; string both refuse.
            (should (eq (run "heading.tags"
                             (list :value ["home" "x1"]
                                   :token (tok-for "Parent")))
                        'accepted))
            (should (string-match-p ":home:x1:" (file-text)))
            (should (eq (run "heading.tags"
                             (list :value ["bad tag"]
                                   :token (tok-for "Parent")))
                        'rejected))
            (should (eq (run "heading.tags"
                             (list :value "home" :token (tok-for "Parent")))
                        'rejected))
            ;; prop-set writes and removes through the funnel.
            (should (eq (run "heading.prop-set"
                             (list :name "FOO" :value "baz"
                                   :token (tok-for "Parent")))
                        'accepted))
            ;; org aligns drawer values — match the key, not the pad.
            (should (string-match-p ":FOO:[ \t]+baz" (file-text)))
            (should (eq (run "heading.prop-set"
                             (list :name "FOO" :value ""
                                   :token (tok-for "Parent")))
                        'accepted))
            (should-not (string-search ":FOO:" (file-text)))
            (should (eq (run "heading.prop-set"
                             (list :name "" :value "x" :token "t"))
                        'rejected))
            ;; duplicate then delete: durable both ways, even among
            ;; duplicate titles (pos+headline resolution).
            (should (eq (run "heading.duplicate"
                             (list :token (tok-for "Second")))
                        'accepted))
            (should (= 2 (with-temp-buffer
                           (insert (file-text))
                           (count-matches "^\\* Second$" (point-min)
                                          (point-max)))))
            (should (eq (run "heading.delete"
                             (list :token (tok-for "Second")))
                        'accepted))
            (should (= 1 (with-temp-buffer
                           (insert (file-text))
                           (count-matches "^\\* Second$" (point-min)
                                          (point-max)))))
            ;; heading.clock-in rides the same classifier: a live token
            ;; clocks in and answers accepted, an absent one is stale.
            ;; `org-clock-in' is stubbed — a real clock would outlive
            ;; this test's vault.
            (let ((clocked 0))
              (cl-letf (((symbol-function 'org-clock-in)
                         (lambda (&rest _) (cl-incf clocked))))
                (should (eq (run "heading.clock-in"
                                 (list :token (tok-for "Parent")))
                            'accepted))
                (should (= clocked 1))
                (should (eq (run "heading.clock-in" '(:token "o0-swept"))
                            'stale))
                (should (eq (run "heading.clock-in" nil) 'stale))
                (should (= clocked 1))))
            ;; D2 over the direct arms: the only legitimate push sites
            ;; in this file are inside continuations the stub never
            ;; runs, so nothing above may have pushed inside a dispatch
            ;; extent (a rootless push would no-op unnoticed).
            (should (zerop pushes))
            ;; detail.save: durable rewrite + a re-anchoring re-push.
            (let ((before (length continuations)))
              (should (eq (run "detail.save"
                               (list :value "* Parent2\nnew body\n"
                                     :token (tok-for "Parent")))
                          'accepted))
              (should (string-search "new body" (file-text)))
              (should (string-search "* Parent2" (file-text)))
              (should (= (length continuations) (1+ before))))
            (should (eq (run "detail.save" '(:value 5 :token "x"))
                        'rejected))
            (should (eq (run "detail.save"
                             (list :value "* X\n" :token "junk"))
                        'stale))
            ;; A value whose leading stars the user deleted is refused
            ;; BEFORE the region is touched — and before the stale arm,
            ;; so shape wins over a swept token.  This failure is
            ;; destructive rather than merely a wrong answer: the
            ;; delete+insert would leave an unsaved mutation in the
            ;; buffer for the next unrelated save to flush.
            (let* ((buf (find-file-noselect file))
                   (before (file-text)))
              (should (eq (run "detail.save"
                               (list :value "no stars here"
                                     :token (tok-for "Parent2")))
                          'rejected))
              (should-not (buffer-modified-p buf))
              (should (equal (file-text) before))
              (should (string-search "* Parent2" (file-text)))
              ;; Shape first: a de-starred value with a SWEPT token
              ;; answers rejected, never stale.
              (should (eq (run "detail.save"
                               '(:value "no stars here" :token "o0-swept"))
                          'rejected))
              (should (equal (file-text) before)))
            ;; Bridged flows: a continuation is scheduled, nothing
            ;; prompts inside the dispatch extent.
            (should (eq (run "heading.refile"
                             (list :token (tok-for "Parent2")))
                        'accepted))
            (should (eq (run "heading.add-note"
                             (list :token (tok-for "Parent2")))
                        'accepted))
            (should (eq (run "heading.prop-add"
                             (list :token (tok-for "Parent2")))
                        'accepted))
            (should (eq (run "heading.refile" '(:token "junk")) 'stale))
            ;; Dialog verbs refuse without a client; bad types reject.
            (should (eq (run "heading.props.show"
                             (list :token (tok-for "Parent2")))
                        'rejected))
            (should (eq (run "detail.planning.edit"
                             (list :token (tok-for "Parent2")
                                   :type "SCHEDULED"))
                        'rejected))
            (should (eq (run "detail.planning.edit"
                             (list :token (tok-for "Parent2")
                                   :type "JUNK"))
                        'rejected))
            (should (eq (run "files.properties.show" (list :file file))
                        'rejected))
            (should (eq (run "files.properties.show"
                             '(:file "/nope/x.org"))
                        'rejected))
            ;; link.open: shape gate, then a deferred open.
            (should (eq (run "org.link.open" '(:link "")) 'rejected))
            (should (eq (run "org.link.open" '(:link 5)) 'rejected))
            (should (eq (run "org.link.open"
                             '(:link "https://example.com"))
                        'accepted))
            ;; toggle-read is the single writer of the mode flag.
            (should (eq (run "detail.toggle-read" nil) 'accepted))
            (should-not glasspane-ui--detail-read-mode)
            (should (eq (run "detail.toggle-read" nil) 'accepted))
            (should glasspane-ui--detail-read-mode)
            ;; files.properties.save: captured fields land as keywords,
            ;; durably, before `accepted'; no fields rejects.
            (should (eq (run "files.properties.save" (list :file file)
                             '(:fields (:file-prop-title "Renamed"
                                        :file-prop-category "cat")))
                        'accepted))
            (should (string-search "#+TITLE: Renamed" (file-text)))
            (should (string-search "#+CATEGORY: cat" (file-text)))
            (should (eq (run "files.properties.save" (list :file file))
                        'rejected))
            ;; The pushed screen: reader mode, editor mode, dead ref.
            (let ((ref (with-current-buffer (find-file-noselect file)
                         (org-with-wide-buffer
                          (goto-char (point-min))
                          (re-search-forward "Parent2")
                          (ebp-org-ref-at-point)))))
              (let* ((glasspane-ui--detail-read-mode t)
                     (screen (glasspane-detail--screen ref nil))
                     (json (jetpacs-node->canonical-json screen)))
                (should (equal (plist-get screen :t) "scaffold"))
                (should (string-search "Parent2" json))
                (should (string-search "heading.todo-set" json))
                (should (string-search "jetpacs.org.archive" json))
                (should (string-search "detail.planning.edit" json))
                (should (string-search "files.properties.show" json)))
              (let* ((glasspane-ui--detail-read-mode nil)
                     (json (jetpacs-node->canonical-json
                            (glasspane-detail--screen ref nil))))
                (should (string-search "\"editor\"" json))
                (should (string-search "detail.save" json))
                (should (string-search "\"ttl_s\"" json))
                (should (string-search "\"dedupe\"" json))))
            (let ((json (jetpacs-node->canonical-json
                         (glasspane-detail--screen
                          '(:id nil :file "/gone/nope.org" :pos 1
                            :headline "X")
                          nil))))
              (should (string-search "Heading moved or gone" json)))))
      (ebp-org-cache-invalidate)
      (ebp-org-teardown-owner "glasspane")
      (ebp-org-teardown-owner jetpacs-org-dialogs-owner)
      (dolist (buf (buffer-list))
        (let ((f (buffer-file-name buf)))
          (when (and f (string-prefix-p (file-name-as-directory
                                         (file-truename vault))
                                        (file-truename f)))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf))))
      (delete-directory vault t))))

(ert-deftest glasspane-test-detail-vulpea-noop ()
  "With vulpea ABSENT — this harness's permanent condition — the two
index touchpoints refile and (via the rebound engine save seam)
archive share are silent no-ops that still land durably on disk: the
seam saves synchronously, and the bridged refile flow moves the
subtree between files with no vulpea in sight."
  (require 'glasspane-detail)
  (should-not (featurep 'vulpea))
  (should-not (fboundp 'vulpea-db-update-file))
  (glasspane-detail-register)
  (let* ((vault (make-temp-file "glasspane-vault" t))
         (src (expand-file-name "src.org" vault))
         (dst (expand-file-name "dst.org" vault))
         (org-directory vault)
         (org-agenda-files (list src dst))
         (ebp-org-roots nil)
         (org-refile-targets `(((,dst) :maxlevel . 1)))
         (org-refile-use-outline-path nil)
         (notified nil))
    (unwind-protect
        (progn
          (with-temp-file src
            (insert "#+TITLE: Src\n* TODO Move me\nbody\n"))
          (with-temp-file dst (insert "#+TITLE: Dst\n* Inbox\n"))
          (ebp-org-cache-invalidate)
          ;; The engine save seam is rebound to the app funnel and
          ;; saves synchronously with the index arm a no-op.
          (should (eq ebp-org-file-save-function
                      #'glasspane-detail--file-save))
          (with-current-buffer (find-file-noselect src)
            (org-with-wide-buffer
             (goto-char (point-max))
             (insert "extra line\n"))
            (funcall ebp-org-file-save-function (current-buffer))
            (should-not (buffer-modified-p)))
          (should (string-search "extra line"
                                 (with-temp-buffer
                                   (insert-file-contents src)
                                   (buffer-string))))
          ;; The bridged refile flow, bridge stubbed open: the subtree
          ;; moves between files, both save, nothing reaches vulpea.
          (let ((ref (with-current-buffer (find-file-noselect src)
                       (org-with-wide-buffer
                        (goto-char (point-min))
                        (re-search-forward "Move me")
                        (ebp-org-ref-at-point)))))
            (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p)
                       (lambda () t))
                      ((symbol-function 'completing-read)
                       (lambda (_prompt collection &rest _)
                         (car collection)))
                      ((symbol-function 'jetpacs-shell-notify)
                       (lambda (text &rest _) (push text notified)))
                      ((symbol-function 'jetpacs-shell-push)
                       (lambda (&rest _) nil))
                      ((symbol-function 'jetpacs-chrome-pop-screen)
                       (lambda (&rest _) nil)))
              (glasspane-detail--refile-flow
               ref '(:surface "app:glasspane"))))
          (should (cl-some (lambda (s) (string-search "Refiled" s))
                           notified))
          (should (string-search "Move me"
                                 (with-temp-buffer
                                   (insert-file-contents dst)
                                   (buffer-string))))
          (should-not (string-search "Move me"
                                     (with-temp-buffer
                                       (insert-file-contents src)
                                       (buffer-string)))))
      (ebp-org-cache-invalidate)
      (dolist (buf (buffer-list))
        (let ((f (buffer-file-name buf)))
          (when (and f (string-prefix-p (file-name-as-directory
                                         (file-truename vault))
                                        (file-truename f)))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf))))
      (delete-directory vault t))))

;;;; G5 — daily surfaces: glasspane-dates.el, glasspane-agenda.el,
;;;; glasspane-journal.el, glasspane-capture.el

(ert-deftest glasspane-test-dates-helpers ()
  "The app-local date module (FOUNDATION-GAPS #10): pure string-in
string-out arithmetic — noon-anchored against DST flips, positional
parsing, month shifts clamped into the target month, locale-proof
English month abbreviations."
  (let ((decoded (decode-time (glasspane-dates-encode "2026-08-13"))))
    (should (= (decoded-time-hour decoded) 12))
    (should (= (decoded-time-day decoded) 13))
    (should (= (decoded-time-month decoded) 8))
    (should (= (decoded-time-year decoded) 2026)))
  ;; Day/week shifts cross month and year boundaries.
  (should (equal (glasspane-dates-shift "2026-08-13" 1 'day) "2026-08-14"))
  (should (equal (glasspane-dates-shift "2026-08-13" -1 'day) "2026-08-12"))
  (should (equal (glasspane-dates-shift "2026-01-31" 1 'day) "2026-02-01"))
  (should (equal (glasspane-dates-shift "2026-01-01" -1 'day) "2025-12-31"))
  (should (equal (glasspane-dates-shift "2026-12-31" 1 'day) "2027-01-01"))
  (should (equal (glasspane-dates-shift "2026-08-13" 1 'week) "2026-08-20"))
  (should (equal (glasspane-dates-shift "2026-08-13" 2 'week) "2026-08-27"))
  ;; Month arithmetic clamps into the target month and walks years;
  ;; leap February keeps its 29th.
  (should (equal (glasspane-dates-shift "2026-01-31" 1 'month) "2026-02-28"))
  (should (equal (glasspane-dates-shift "2024-01-31" 1 'month) "2024-02-29"))
  (should (equal (glasspane-dates-shift "2026-01-15" -1 'month) "2025-12-15"))
  (should (equal (glasspane-dates-shift "2026-12-15" 1 'month) "2027-01-15"))
  (should (equal (glasspane-dates-shift "2026-11-01" 3 'month) "2027-02-01"))
  ;; Format rides format-time-string; the C locale pins the weekday.
  (should (equal (glasspane-dates-format "2026-08-13" "%Y/%m/%d")
                 "2026/08/13"))
  (let ((system-time-locale "C"))
    (should (equal (glasspane-dates-format "2000-01-01" "%a %Y") "Sat 2000")))
  (should (equal (glasspane-dates-month-abbrev 1) "Jan"))
  (should (equal (glasspane-dates-month-abbrev 12) "Dec"))
  (should-not (glasspane-dates-month-abbrev 0))
  (should-not (glasspane-dates-month-abbrev 13))
  (should-not (glasspane-dates-month-abbrev "3")))

(ert-deftest glasspane-test-agenda-formatters ()
  "The pure agenda formatters over fixture alists: the compact meta
line, the type icon/label maps, the card date label/row, the composed
month fallback grid, the mode list, and the in-screen count that
replaced the tab badge (FOUNDATION-GAPS #5)."
  ;; widget-item-meta: qualifier cleanup, redundant-qualifier drop,
  ;; time precedence, empty degrade.
  (should (equal (glasspane-ui--widget-item-meta
                  '((extra . "Sched. 3x: ") (file . "/v/tasks.org")) nil)
                 "Sched. 3x · tasks.org"))
  (should (equal (glasspane-ui--widget-item-meta
                  '((extra . "Scheduled") (file . "/v/tasks.org")) nil)
                 "tasks.org"))
  (should (equal (glasspane-ui--widget-item-meta
                  '((extra . "In 3 d.") (file . "/v/t.org")) "09:15")
                 "09:15 · t.org"))
  (should (equal (glasspane-ui--widget-item-meta '((extra . "Deadline")) nil)
                 ""))
  ;; The icon/label maps.
  (should (equal (glasspane-ui--widget-agenda-icon "upcoming-deadline")
                 "deadline"))
  (should (equal (glasspane-ui--widget-agenda-icon "past-scheduled")
                 "scheduled"))
  (should (equal (glasspane-ui--widget-agenda-icon nil) "event"))
  (should (equal (glasspane-ui--agenda-type-icon "past-scheduled")
                 '("history" . "#E53935")))
  (should (equal (car (glasspane-ui--agenda-type-icon "deadline")) "flag"))
  (should-not (glasspane-ui--agenda-type-icon "timestamp"))
  (should (equal (glasspane-ui--agenda-type-label "past-scheduled")
                 "overdue"))
  (should-not (glasspane-ui--agenda-type-label "block"))
  ;; Card date label: month abbrev + optional ebp-org-ts-time time.
  (should (equal (glasspane-ui--card-date-label "<2026-08-13 Thu 14:00>")
                 "Aug 13 14:00"))
  (should (equal (glasspane-ui--card-date-label "<2026-02-01 Sun>") "Feb 1"))
  (should-not (glasspane-ui--card-date-label "junk"))
  ;; Card date row: both stamps render; no stamps, no row.
  (let ((row (glasspane-ui--card-date-row
              '((scheduled . "<2026-08-13 Thu>")
                (deadline . "<2026-08-20 Thu>")))))
    (should row)
    (let ((json (jetpacs-node->canonical-json row)))
      (should (string-search "Aug 13" json))
      (should (string-search "Aug 20" json))))
  (should-not (glasspane-ui--card-date-row '((headline . "x"))))
  ;; Month fallback: Feb 2026 stops at 28 cells, the selected day is
  ;; tinted, taps carry the ISO date, the select verb is overridable.
  (let* ((grid (glasspane-agenda--month-fallback
                '(("2026-02-14" . (((headline . "x")))))
                "2026-02-15" "2026-02-14"))
         (json (jetpacs-node->canonical-json grid)))
    (should (string-search "\"28\"" json))
    (should-not (string-search "\"29\"" json))
    (should (string-search "#1976D2" json))
    (should (string-search "agenda.select-date" json))
    (should (string-search "2026-02-01" json)))
  (should (string-search
           "views.select-date"
           (jetpacs-node->canonical-json
            (glasspane-agenda--month-fallback nil "2026-02-15" "2026-02-14"
                                              "views.select-date"))))
  ;; Modes: the spans, then the saved searches, display order.
  (let ((glasspane-org-custom-agendas '(("Errands" . "tags:errand"))))
    (should (equal (glasspane-agenda--modes)
                   '("day" "week" "month" "Errands"))))
  ;; The page count is a TOKEN budget: each page mints two sets against
  ;; a per-owner cap, and the mint signals on overflow — so a user with
  ;; twenty saved searches gets the first eight, never a dead body.
  (let ((glasspane-org-custom-agendas
         (cl-loop for i from 1 to 20
                  collect (cons (format "S%d" i) "tags:x"))))
    (should (= (length (glasspane-agenda--modes)) 11))
    (should (equal (car (last (glasspane-agenda--modes))) "S8")))
  ;; The in-screen count reads the memoised day extraction and
  ;; swallows its errors.
  (cl-letf (((symbol-function 'glasspane-org--agenda-items)
             (lambda (&rest _) '(a b))))
    (should (= (glasspane-agenda--today-count) 2)))
  (cl-letf (((symbol-function 'glasspane-org--agenda-items)
             (lambda (&rest _) (error "boom"))))
    (should (= (glasspane-agenda--today-count) 0))))

(ert-deftest glasspane-test-agenda-tokenize ()
  "The agenda's bulk mint: an item whose file left the org roots is
filtered BEFORE the mint (the mint would signal and kill the whole
body build) and still renders — untappable, with neither cell — while
an allowed item carries BOTH, the tap token in the app's own scope and
the archive token in the disjoint \"glasspane-SET\" name the base
`jetpacs.org.archive' resolves under."
  (require 'glasspane-agenda)
  (let* ((vault (make-temp-file "glasspane-agenda" t))
         (file (expand-file-name "tasks.org" vault))
         (outside (make-temp-file "glasspane-outside" nil ".org"))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots nil))
    (unwind-protect
        (progn
          (with-temp-file file (insert "#+TITLE: T\n* TODO Inside\n"))
          (with-temp-file outside (insert "#+TITLE: O\n* TODO Outside\n"))
          (ebp-org-cache-invalidate)
          (should (ebp-org-file-allowed-p file))
          (should-not (ebp-org-file-allowed-p outside))
          (let* ((items
                  (list `((headline . "Inside")
                          (ref . (:file ,file :pos 1 :headline "Inside")))
                        `((headline . "Outside")
                          (ref . (:file ,outside :pos 1
                                  :headline "Outside")))))
                 (out (glasspane-agenda--tokenize items "t-agenda")))
            ;; The refused item is still on screen, just without arms.
            (should (= (length out) 2))
            (let ((refused (nth 1 out)))
              (should (equal (alist-get 'headline refused) "Outside"))
              (should-not (alist-get 'token refused))
              (should-not (alist-get 'archive-token refused)))
            (let* ((armed (nth 0 out))
                   (tap (alist-get 'token armed))
                   (arch (alist-get 'archive-token armed)))
              (should (stringp tap))
              (should (stringp arch))
              (should (equal (plist-get (ebp-org-token-ref
                                         tap :owner "glasspane")
                                        :headline)
                             "Inside"))
              ;; The two scopes are disjoint: the archive token is the
              ;; dialogs owner's, and neither resolves in the other's.
              (should (ebp-org-token-ref
                       arch :owner jetpacs-org-dialogs-owner))
              (should-not (ebp-org-token-ref arch :owner "glasspane"))
              (should-not (ebp-org-token-ref
                           tap :owner jetpacs-org-dialogs-owner)))))
      (ignore-errors
        (ebp-org-ref-tokens nil :set "t-agenda" :owner "glasspane")
        (ebp-org-ref-tokens nil :set "glasspane-t-agenda"
                            :owner jetpacs-org-dialogs-owner))
      (ebp-org-cache-invalidate)
      (when (file-exists-p outside) (delete-file outside))
      (delete-directory vault t))))

(ert-deftest glasspane-test-agenda-handler-matrix ()
  "Every G5 agenda verb, funcalled from the handler table with plist
args and no client, answers a SPEC 14.4 status — then the sharp edges:
the single-writer defvars, month-clamped nav, the deferred open
pushes, and the reminder sync's grant gate + suppress cache.  (The
TODO-sequence writers left with §3 step 2 — the foundation suite owns
their arms now.)"
  (glasspane-agenda-register)
  (let ((glasspane-org-custom-agendas '(("Errands" . "tags:errand")))
        (glasspane-agenda--mode "day")
        (glasspane-agenda--tasks-filter "ALL")
        (glasspane-ui-agenda-anchor nil)
        (jetpacs-settings--dialog nil)
        (org-todo-keywords '((sequence "TODO" "|" "DONE")))
        (saved nil) (continuations nil))
    (cl-letf (((symbol-function 'jetpacs-settings-save-variable)
               (lambda (sym val)
                 (push (cons sym val) saved) (set sym val) val))
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
        (dolist (name glasspane-agenda--verbs)
          (should (memq (run name nil nil) '(accepted stale rejected))))
        ;; agenda.set-mode: chip name, tabs float index, junk.
        (should (eq (run "agenda.set-mode" '(:mode "week")) 'accepted))
        (should (equal glasspane-agenda--mode "week"))
        (should (eq (run "agenda.set-mode" '(:value 3.0)) 'accepted))
        (should (equal glasspane-agenda--mode "Errands"))
        (should (eq (run "agenda.set-mode" '(:mode "nope")) 'rejected))
        (should (eq (run "agenda.set-mode" '(:value 99)) 'rejected))
        ;; Only the WHOLE float is org.json's trailing .0; a genuinely
        ;; fractional index is a malformed event, not a rounding job.
        (should (eq (run "agenda.set-mode" '(:value 0.7)) 'rejected))
        ;; agenda.nav: span-aware shifts off the shared anchor; month
        ;; steps re-anchor on the 1st; junk dir rejects.
        (setq glasspane-agenda--mode "day"
              glasspane-ui-agenda-anchor "2026-08-13")
        (should (eq (run "agenda.nav" '(:dir 1)) 'accepted))
        (should (equal glasspane-ui-agenda-anchor "2026-08-14"))
        (setq glasspane-agenda--mode "week")
        (should (eq (run "agenda.nav" '(:dir -1)) 'accepted))
        (should (equal glasspane-ui-agenda-anchor "2026-08-07"))
        (setq glasspane-agenda--mode "month"
              glasspane-ui-agenda-anchor "2026-01-31")
        (should (eq (run "agenda.nav" '(:dir 1)) 'accepted))
        (should (equal glasspane-ui-agenda-anchor "2026-02-01"))
        (should (eq (run "agenda.nav" '(:dir "x")) 'rejected))
        (should (eq (run "agenda.nav" '(:dir 0.7)) 'rejected))
        (should (equal glasspane-ui-agenda-anchor "2026-02-01"))
        ;; tasks.filter: the defvar is the single writer's cell.
        (should (eq (run "tasks.filter" '(:filter "DONE")) 'accepted))
        (should (equal glasspane-agenda--tasks-filter "DONE"))
        (should (eq (run "tasks.filter" '(:filter 5)) 'rejected))
        ;; The open verbs park their pushes past the dispatch extent.
        (let ((before (length continuations)))
          (should (eq (run "agenda.open" nil '(:surface "glasspane"))
                      'accepted))
          (should (eq (run "tasks.open" nil nil) 'accepted))
          (should (= (length continuations) (+ 2 before))))
        ;; Reminder sync, ungranted: the wire is never touched and the
        ;; suppress cache stays unset.
        (let ((calls 0)
              (glasspane-agenda--last-reminders 'unset))
          (cl-letf (((symbol-function 'jetpacs-client) (lambda () t))
                    ((symbol-function 'jetpacs-granted-p)
                     (lambda (&rest _) nil))
                    ((symbol-function 'jetpacs-reminders-set)
                     (lambda (&rest _) (cl-incf calls))))
            (glasspane-agenda--sync-reminders)
            (should (= calls 0))
            (should (eq glasspane-agenda--last-reminders 'unset))))
        ;; Granted: one set goes out, the cache adopts only in the
        ;; confirmed callback, and the identical next sync suppresses.
        (let ((sent nil)
              (glasspane-agenda--last-reminders 'unset))
          (cl-letf (((symbol-function 'jetpacs-client) (lambda () t))
                    ((symbol-function 'jetpacs-granted-p)
                     (lambda (&rest _) t))
                    ((symbol-function 'glasspane-org--upcoming-reminders)
                     (lambda (&rest _) '((:id "r1"))))
                    ((symbol-function 'jetpacs-reminders-set)
                     (cl-function
                      (lambda (rems &key owner callback)
                        (push (cons owner rems) sent)
                        (funcall callback 1 nil)))))
            (glasspane-agenda--sync-reminders)
            (should (equal sent '(("glasspane" . ((:id "r1"))))))
            (should (equal glasspane-agenda--last-reminders '((:id "r1"))))
            (glasspane-agenda--sync-reminders)
            (should (= (length sent) 1))))))))

(ert-deftest glasspane-test-agenda-reminder-hook-follows-mitigation-flag ()
  "GR-0 installs Glasspane's reminder hook iff its flag is enabled."
  (unwind-protect
      (progn
        (glasspane-agenda-unregister)
        (let ((glasspane-agenda-reminders-enabled nil))
          (glasspane-agenda-register)
          (should-not (memq #'glasspane-agenda--sync-reminders
                            jetpacs-shell-after-push-hook))
          (glasspane-agenda-unregister))
        (let ((glasspane-agenda-reminders-enabled t))
          (glasspane-agenda-register)
          (should (memq #'glasspane-agenda--sync-reminders
                        jetpacs-shell-after-push-hook))))
    (glasspane-agenda-unregister)
    (glasspane-agenda-register)))

(defun glasspane-test--journal-vault ()
  "A throwaway vault directory for journal fixtures."
  (make-temp-file "glasspane-journal" t))

(defun glasspane-test--journal-cleanup (vault)
  "Drop the org memo, kill VAULT's visiting buffers, delete VAULT."
  (ebp-org-cache-invalidate)
  (dolist (buf (buffer-list))
    (let ((f (buffer-file-name buf)))
      (when (and f (string-prefix-p (file-name-as-directory
                                     (file-truename vault))
                                    (file-truename f)))
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf))))
  (delete-directory vault t))

(ert-deftest glasspane-test-journal-datetree ()
  "--day-pos/--append against a real temp datetree: an absent file is
nil (never an error), the first append creates the file and the
levels, same-day appends share ONE day heading in order — and the
whole journal screen builds and round-trips the canonical encoding."
  (let* ((vault (glasspane-test--journal-vault))
         (org-directory vault)
         (org-agenda-files nil)
         (ebp-org-roots nil)
         (glasspane-journal-file nil)
         (glasspane-journal--date nil)
         (today (glasspane-journal--today)))
    (unwind-protect
        (progn
          (should-not (glasspane-journal--day-pos today))
          (glasspane-journal--append "First entry" today)
          (should (integerp (glasspane-journal--day-pos today)))
          (should-not (glasspane-journal--day-pos "1999-01-01"))
          (glasspane-journal--append "Second entry" today)
          (with-temp-buffer
            (insert-file-contents (expand-file-name "journal.org" vault))
            ;; Both items landed, in order, under ONE day heading.
            (goto-char (point-min))
            (should (re-search-forward "^- First entry$" nil t))
            (should (re-search-forward "^- Second entry$" nil t))
            (should (= 1 (count-matches
                          (format "^\\*+[ \t]+%s\\(?:[ \t]\\|$\\)"
                                  (regexp-quote today))
                          (point-min) (point-max)))))
          ;; The screen clears the same serialization bar as G0's home.
          (let ((json (jetpacs-node->canonical-json
                       (glasspane-journal-screen nil))))
            (should (stringp json))
            (should (string-search "journal-capture" json))
            (should (string-search "First entry" json))
            ;; The capture FAB (FOUNDATION-GAPS #2): every daily
            ;; surface carries the org.capture.show entry point, or
            ;; capture is unreachable from the rendered UI.
            (should (string-search "org.capture.show" json))))
      (glasspane-test--journal-cleanup vault))))

(ert-deftest glasspane-test-journal-carried-query ()
  "The carry-over tree passes the wire vet UNCHANGED, the query finds
exactly the overdue TODO, and the section's bulk mint lands in the
\(glasspane . journal-carried) replace-set (S5)."
  (should (equal (ebp-org--vet-query '(and (todo) (scheduled :to -1)))
                 '(and (todo) (scheduled :to -1))))
  (let* ((vault (glasspane-test--journal-vault))
         (file (expand-file-name "tasks.org" vault))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots nil)
         (overdue (glasspane-dates-shift (glasspane-journal--today) -2 'day))
         (upcoming (glasspane-dates-shift (glasspane-journal--today) 2 'day)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: Tasks\n\n"
                    "* TODO Overdue thing\n"
                    (format "SCHEDULED: <%s>\n" overdue)
                    "* TODO Future thing\n"
                    (format "SCHEDULED: <%s>\n" upcoming)
                    "* DONE Finished thing\n"
                    (format "SCHEDULED: <%s>\n" overdue)))
          (ebp-org-cache-invalidate)
          (let ((items (glasspane-journal--carried-over)))
            (should (= (length items) 1))
            (should (equal (alist-get 'headline (car items))
                           "Overdue thing")))
          (let ((nodes (glasspane-journal--carried-section)))
            (should nodes)
            (should (string-search
                     "Carried over (1)"
                     (mapconcat #'jetpacs-node->canonical-json nodes "")))
            (should (= 1 (length (gethash (cons "glasspane" "journal-carried")
                                          ebp-org--token-sets))))
            ;; The minted token resolves back to the overdue heading.
            (let* ((tok (car (gethash (cons "glasspane" "journal-carried")
                                      ebp-org--token-sets)))
                   (ref (ebp-org-token-ref tok :owner "glasspane")))
              (should (equal (plist-get ref :headline) "Overdue thing")))))
      (glasspane-test--journal-cleanup vault))))

(ert-deftest glasspane-test-journal-handlers ()
  "Every journal verb answers a SPEC 14.4 status: nav non-integer
rejects (whole floats coerce), goto validates the full day shape,
capture rejects empty input and answers `accepted' only once the
append is ON DISK, open defers its push (D2) — and the unregister
sweep leaves no handler and no settings section behind."
  (glasspane-journal-register)
  ;; §3 step 2 consolidation: journal registers NO section of its own;
  ;; the landing row lives in glasspane-ui's "Glasspane" block.
  (should-not (alist-get "Journal" jetpacs-settings-registry nil nil #'equal))
  (let* ((vault (glasspane-test--journal-vault))
         (org-directory vault)
         (org-agenda-files nil)
         (ebp-org-roots nil)
         (glasspane-journal-file (expand-file-name "journal.org" vault))
         (glasspane-journal--date nil)
         (continuations nil))
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-flow-continue)
                   (lambda (fn) (push fn continuations) nil))
                  ((symbol-function 'jetpacs-shell-notify)
                   (lambda (&rest _) nil))
                  ((symbol-function 'jetpacs-toast) (lambda (&rest _) nil)))
          (cl-flet ((run (name args &optional params)
                      (let ((handler (gethash name jetpacs-action-handlers)))
                        (should handler)
                        (funcall handler args params))))
            ;; The whole table answers statuses on bare nil/nil input.
            (dolist (name glasspane-journal--verbs)
              (should (memq (run name nil nil)
                            '(accepted stale rejected))))
            ;; journal.nav: integers move the day, whole floats coerce
            ;; (org.json's trailing .0), junk rejects without writing.
            (setq glasspane-journal--date "2026-08-10")
            (should (eq (run "journal.nav" '(:delta 1)) 'accepted))
            (should (equal glasspane-journal--date "2026-08-11"))
            (should (eq (run "journal.nav" '(:delta -1.0)) 'accepted))
            (should (equal glasspane-journal--date "2026-08-10"))
            (should (eq (run "journal.nav" '(:delta "x")) 'rejected))
            ;; Only the WHOLE float is org.json's trailing .0; half a
            ;; day is a malformed event, not a rounding job.
            (should (eq (run "journal.nav" '(:delta 0.5)) 'rejected))
            (should (eq (run "journal.nav" nil) 'rejected))
            (should (equal glasspane-journal--date "2026-08-10"))
            ;; journal.goto: the picker's :value must be a full day.
            (should (eq (run "journal.goto" '(:value "2026-01-02"))
                        'accepted))
            (should (equal glasspane-journal--date "2026-01-02"))
            (should (eq (run "journal.goto" '(:value "2026-1-2"))
                        'rejected))
            (should (eq (run "journal.goto" '(:value 42)) 'rejected))
            ;; journal.today: back to the nil-means-today rest state.
            (should (eq (run "journal.today" nil) 'accepted))
            (should-not glasspane-journal--date)
            ;; journal.capture: whitespace-only and non-string reject
            ;; with nothing written...
            (should (eq (run "journal.capture" '(:value "   ")) 'rejected))
            (should (eq (run "journal.capture" '(:value 42)) 'rejected))
            (should-not (file-exists-p glasspane-journal-file))
            ;; ...and a real entry is ON DISK when accepted returns.
            (should (eq (run "journal.capture"
                             '(:value "  Ship the port  "
                               :date "2026-08-13"))
                        'accepted))
            (with-temp-buffer
              (insert-file-contents glasspane-journal-file)
              (goto-char (point-min))
              (should (re-search-forward "^- Ship the port$" nil t))
              (should (string-search "2026-08-13" (buffer-string))))
            ;; SPEC 23.2: wire text is neutralized before it becomes
            ;; org structure.  The append lands at end-of-subtree, so
            ;; an embedded newline would promote the payload out of the
            ;; list item into a heading of its own.
            (cl-flet ((headings ()
                        (with-temp-buffer
                          (insert-file-contents glasspane-journal-file)
                          (count-matches "^\\*+ " (point-min) (point-max)))))
              (let ((before (headings)))
                (should (eq (run "journal.capture"
                                 '(:value "hello\n* Evil"
                                   :date "2026-08-13"))
                            'accepted))
                (should (= (headings) before))
                (with-temp-buffer
                  (insert-file-contents glasspane-journal-file)
                  (goto-char (point-min))
                  (should (re-search-forward "^- hello \\* Evil$" nil t)))))
            ;; journal.open: accepted on the strength of the deferred
            ;; push — zero pushes inside the dispatch extent (D2).
            (let ((before (length continuations)))
              (should (eq (run "journal.open" nil
                               '(:surface "app:glasspane"))
                          'accepted))
              (should (= (length continuations) (1+ before))))
            ;; The sweep — then re-register, so suite order never
            ;; matters.
            (glasspane-journal-unregister)
            (dolist (name glasspane-journal--verbs)
              (should-not (gethash name jetpacs-action-handlers)))
            (should-not (alist-get "Journal" jetpacs-settings-registry
                                   nil nil #'equal))
            (glasspane-journal-register)))
      (glasspane-test--journal-cleanup vault))))

(ert-deftest glasspane-test-capture-is-downstream-rollback-adapter ()
  "The default app cannot displace native capture; the two flags reverse it."
  (should-not (default-value 'glasspane-capture-enabled))
  (unwind-protect
      (progn
        ;; Normal post-cutover composition: the disabled adapter neither
        ;; overwrites nor unregisters the upstream owner.
        (let ((jetpacs-org-capture-enabled t)
              (glasspane-capture-enabled nil))
          (jetpacs-org-capture-register)
          (glasspane-capture-register))
        (should (eq (gethash "org.capture.show" jetpacs-action-handlers)
                    #'jetpacs-org-capture--on-show))
        (should (equal (jetpacs--owner-of "action" "org.capture.show")
                       "org-mode"))
        (glasspane-capture-unregister)
        (should (eq (gethash "org.capture.show" jetpacs-action-handlers)
                    #'jetpacs-org-capture--on-show))
        ;; Scripted reverse: upstream off first, then the downstream adapter on.
        (let ((jetpacs-org-capture-enabled nil)
              (glasspane-capture-enabled t))
          (jetpacs-org-capture-register)
          (glasspane-capture-register))
        (should (eq (gethash "org.capture.show" jetpacs-action-handlers)
                    #'glasspane-capture--on-show))
        (should (equal (jetpacs--owner-of "action" "org.capture.show")
                       "glasspane")))
    (let ((glasspane-capture-enabled nil))
      (glasspane-capture-register))
    (let ((jetpacs-org-capture-enabled t))
      (jetpacs-org-capture-register))))

;;;; G6 — query surfaces: glasspane-views.el

(ert-deftest glasspane-test-views-board ()
  "Board columns keep global keyword order, append file-local
strangers in encounter order, and park no-state last; the single-file
guard demands one file, integer positions, and headline levels; the
done predicate and priority badge are the shared card vocabulary —
all pure, over fixture alists."
  (require 'glasspane-views)
  ;; `org-todo-keywords-1' is defvar-local: bind the DEFAULT binding
  ;; explicitly — `glasspane-views--board-columns' reads it, since the
  ;; builder must see the global sequence whatever buffer it runs in.
  (let ((old (default-value 'org-todo-keywords-1)))
    (unwind-protect
        (progn
          (setq-default org-todo-keywords-1 '("TODO" "NEXT" "DONE"))
          (should (equal (glasspane-views--board-columns
                          '(((todo . "NEXT")) ((todo . "WIP"))
                            ((todo . "TODO")) ((todo . "NEXT"))
                            ((todo . nil))))
                         '("TODO" "NEXT" "WIP" "")))
          (should-not (glasspane-views--board-columns nil))
          ;; Every present state gets a column even when none is global.
          (should (equal (glasspane-views--board-columns
                          '(((todo . "MAYBE"))))
                         '("MAYBE"))))
      (setq-default org-todo-keywords-1 old)))
  ;; The single-file guard.
  (let ((one '(((file . "/v/a.org") (pos . 10) (level . 1))
               ((file . "/v/a.org") (pos . 40) (level . 2)))))
    (should (equal (glasspane-views--single-file one) "/v/a.org"))
    (should-not (glasspane-views--single-file nil))
    (should-not (glasspane-views--single-file
                 (cons '((file . "/v/b.org") (pos . 5) (level . 1)) one)))
    ;; A file-level note (level 0) cannot reorder.
    (should-not (glasspane-views--single-file
                 '(((file . "/v/a.org") (pos . 1) (level . 0)))))
    (should-not (glasspane-views--single-file
                 '(((file . "/v/a.org") (pos . nil) (level . 1))))))
  ;; Done predicate + priority badge.
  (let ((old (default-value 'org-done-keywords)))
    (unwind-protect
        (progn
          (setq-default org-done-keywords '("DONE" "KILLED"))
          (should (glasspane-views--done-p '((todo . "KILLED"))))
          (should-not (glasspane-views--done-p '((todo . "TODO"))))
          (should-not (glasspane-views--done-p '((headline . "no state"))))
          (should (equal (glasspane-views--done-keyword) "DONE")))
      (setq-default org-done-keywords old)))
  (should-not (glasspane-views--priority-span nil))
  (let ((span (glasspane-views--priority-span "A")))
    (should (equal (plist-get span :text) "[A] "))
    (should (equal (plist-get span :font_weight) "bold"))
    (should (equal (plist-get span :color) "#E53935")))
  (should (equal (plist-get (glasspane-views--priority-span "Z") :color)
                 "#9E9E9E"))
  ;; Done headlines degrade to color — no strike span exists (gap #7).
  (let ((old (default-value 'org-done-keywords)))
    (unwind-protect
        (progn
          (setq-default org-done-keywords '("DONE"))
          (let ((spans (glasspane-views--headline-spans
                        '((headline . "Shipped") (todo . "DONE")
                          (priority . "B")))))
            (should (= (length spans) 2))
            (should (equal (plist-get (cadr spans) :color)
                           "on_surface_variant"))))
      (setq-default org-done-keywords old))))

(ert-deftest glasspane-test-views-rendering-roundtrip ()
  "Setting a rendering rebuilds the saved entry without mutating the
value Customize handed out, tolerates hand-authored entries missing
the key, persists through the settings writer, and the read-side
coercion never answers a rendering we don't offer."
  (require 'glasspane-views)
  (let* ((work '((name . "Work") (query . "tags:work") (rendering . "board")))
         (glasspane-saved-views
          (list '((name . "Inbox") (query . "todo:TODO")) work))
         (saved nil))
    (cl-letf (((symbol-function 'jetpacs-settings-save-variable)
               (lambda (sym val) (push (cons sym val) saved) val)))
      ;; A missing rendering key reads as the default.
      (should (equal (glasspane-views--rendering
                      (glasspane-views--get "Inbox"))
                     "list"))
      (glasspane-views--set-rendering "Inbox" "calendar")
      (glasspane-views--persist)
      (should (equal (alist-get 'rendering (glasspane-views--get "Inbox"))
                     "calendar"))
      ;; Exactly one rendering cell after the rebuild.
      (should (= 1 (cl-count 'rendering (glasspane-views--get "Inbox")
                             :key #'car-safe)))
      ;; The untouched sibling is the SAME object Customize handed out.
      (should (eq (glasspane-views--get "Work") work))
      (should (equal (cdr (assq 'glasspane-saved-views saved))
                     glasspane-saved-views))
      ;; Junk in a hand-authored entry coerces at read, not in place.
      (glasspane-views--set-rendering "Work" "sparkline")
      (should (equal (glasspane-views--rendering
                      (glasspane-views--get "Work"))
                     "list")))))

(ert-deftest glasspane-test-views-handler-statuses ()
  "Every views verb answers a SPEC 14.4 status: unknown names are
stale, malformed args rejected, opens/saves accepted on the strength
of deferred work only.  The client-side pieces run stubbed (ui-state
drafts, shell push, flow continuations); tokens mint through the real
offline table.  Both screens build and round-trip the canonical wire
encoding, in the tabs form and the chip fallback, drag list included."
  (require 'glasspane-views)
  (glasspane-views-register)
  (glasspane-views-register)            ; idempotent re-registration
  (let* ((vault (make-temp-file "glasspane-vault" t))
         (file (expand-file-name "tasks.org" vault))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots nil)
         (today (format-time-string "%Y-%m-%d"))
         (glasspane-saved-views
          (list '((name . "Inbox") (query . "todo:TODO,DONE"))
                '((name . "Sexp") (query . (todo "TODO")))
                '((name . "Broken") (query . "(") (rendering . "board"))))
         (glasspane-views--reorder nil)
         (glasspane-views--cal-anchor nil)
         (glasspane-views--cal-selected nil)
         (saved nil) (continuations nil) (pushes nil))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: Tasks\n\n"
                    "* TODO Water the garden :home:\n"
                    (format "SCHEDULED: <%s>\n" today)
                    "* TODO [#A] Call the bank\n"
                    "* DONE Done thing\n"))
          (ebp-org-cache-invalidate)
          (cl-letf (((symbol-function 'jetpacs-settings-save-variable)
                     (lambda (sym val) (push (cons sym val) saved) val))
                    ((symbol-function 'jetpacs-shell-notify)
                     (lambda (&rest _) nil))
                    ((symbol-function 'jetpacs-toast) (lambda (&rest _) nil))
                    ((symbol-function 'jetpacs-shell-push)
                     (lambda (&rest args) (push args pushes) nil))
                    ((symbol-function 'jetpacs-flow-continue)
                     (lambda (fn) (push fn continuations) nil)))
            (cl-flet ((run (name args &optional params)
                        (let ((handler (gethash name jetpacs-action-handlers)))
                          (should handler)
                          (funcall handler args params))))
              ;; The whole table answers statuses on bare nil/nil input.
              (dolist (name glasspane-views--verbs)
                (should (memq (run name nil nil)
                              '(accepted stale rejected))))
              ;; views.open: malformed, gone, real (with state reset).
              (should (eq (run "views.open" '(:name 42)) 'rejected))
              (should (eq (run "views.open" '(:name "Ghost")) 'stale))
              (setq glasspane-views--reorder t
                    glasspane-views--cal-anchor "2020-01-01"
                    glasspane-views--cal-selected "2020-01-02")
              (let ((before (length continuations)))
                (should (eq (run "views.open" '(:name "Inbox")) 'accepted))
                (should (= (length continuations) (1+ before))))
              (should-not glasspane-views--reorder)
              (should-not glasspane-views--cal-anchor)
              (should-not glasspane-views--cal-selected)
              ;; views.hub: a deferred push, nothing else.
              (let ((before (length continuations)))
                (should (eq (run "views.hub" nil nil) 'accepted))
                (should (= (length continuations) (1+ before))))
              ;; The calendar defvars: handlers are the single writer.
              (should (eq (run "views.cal.select-date"
                               '(:value "2026-08-14"))
                          'accepted))
              (should (equal glasspane-views--cal-selected "2026-08-14"))
              (should (eq (run "views.cal.select-date"
                               '(:date "2026-08-15"))
                          'accepted))
              (should (equal glasspane-views--cal-selected "2026-08-15"))
              (should (eq (run "views.cal.select-date" '(:value "junk"))
                          'rejected))
              (should (eq (run "views.cal.set-month" '(:value "2026-09"))
                          'accepted))
              (should (equal glasspane-views--cal-anchor "2026-09-01"))
              (should (eq (run "views.cal.set-month" '(:value "2026-9"))
                          'rejected))
              ;; views.rendering: chips name it, the pager indexes it
              ;; (float-coerced); gone view stale, junk rejected.
              (should (eq (run "views.rendering"
                               '(:name "Inbox" :rendering "board"))
                          'accepted))
              (should (equal (alist-get 'rendering
                                        (glasspane-views--get "Inbox"))
                             "board"))
              (should (assq 'glasspane-saved-views saved))
              (should (eq (run "views.rendering"
                               '(:name "Inbox" :value 2.0))
                          'accepted))
              (should (equal (alist-get 'rendering
                                        (glasspane-views--get "Inbox"))
                             "calendar"))
              (should (eq (run "views.rendering"
                               '(:name "Ghost" :rendering "board"))
                          'stale))
              (should (eq (run "views.rendering"
                               '(:name "Inbox" :rendering "sparkline"))
                          'rejected))
              (should (eq (run "views.rendering" '(:name "Inbox" :value 99))
                          'rejected))
              ;; views.reorder toggles.
              (should (eq (run "views.reorder" nil nil) 'accepted))
              (should glasspane-views--reorder)
              (setq glasspane-views--reorder nil)
              ;; views.save: no client refuses before any read.
              (should (eq (run "views.save" nil nil) 'rejected))
              (let ((drafts '(("views-new-name" . " Fresh ")
                              ("views-new-query" . "tags:home")
                              ("views-new-rendering" . "board"))))
                (cl-letf (((symbol-function 'jetpacs-client)
                           (lambda () t))
                          ((symbol-function 'jetpacs-ui-state)
                           (lambda (id &optional _surface)
                             (cdr (assoc id drafts)))))
                  (should (eq (run "views.save" nil
                                   '(:surface "app:glasspane"))
                              'accepted))
                  (let ((view (glasspane-views--get "Fresh")))
                    (should view)
                    (should (equal (alist-get 'query view) "tags:home"))
                    (should (equal (alist-get 'rendering view) "board")))
                  ;; The deferred repush clears the device drafts.
                  (funcall (car continuations))
                  (should (equal (plist-get (cdar pushes) :reset-input-ids)
                                 glasspane-views--form-ids))
                  ;; Same name replaces, junk rendering coerces.
                  (setcdr (assoc "views-new-rendering" drafts) "sparkline")
                  (should (eq (run "views.save" nil nil) 'accepted))
                  (should (= 1 (cl-count "Fresh" glasspane-saved-views
                                         :key (lambda (v)
                                                (alist-get 'name v))
                                         :test #'equal)))
                  (should (equal (alist-get
                                  'rendering
                                  (glasspane-views--get "Fresh"))
                                 "list"))
                  ;; Blank fields and a broken query refuse.
                  (setcdr (assoc "views-new-name" drafts) "  ")
                  (should (eq (run "views.save" nil nil) 'rejected))
                  (setcdr (assoc "views-new-name" drafts) "X")
                  (setcdr (assoc "views-new-query" drafts) " ")
                  (should (eq (run "views.save" nil nil) 'rejected))
                  (setcdr (assoc "views-new-query" drafts) "(")
                  (should (eq (run "views.save" nil nil) 'rejected))
                  (should-not (glasspane-views--get "X"))))
              ;; views.delete: malformed, gone, real.
              (should (eq (run "views.delete" '(:name 42)) 'rejected))
              (should (eq (run "views.delete" '(:name "Ghost")) 'stale))
              (should (eq (run "views.delete" '(:name "Fresh")) 'accepted))
              (should-not (glasspane-views--get "Fresh")))
            ;; The screens build offline and round-trip the canonical
            ;; encoding.  No client: the advertised probe assumes the
            ;; richer form — tabs pager, curated month grid.
            (let ((json (jetpacs-node->canonical-json
                         (glasspane-views--screen "Inbox" nil))))
              (should (string-search "Inbox" json))
              (should (string-search "Water the garden" json))
              (should (string-search "month_grid" json)))
            ;; The chip-switcher fallback, one rendering per push.
            (cl-letf (((symbol-function 'jetpacs-node-advertised-p)
                       (lambda (&rest _) nil)))
              (dolist (r '("list" "board" "calendar"))
                (glasspane-views--set-rendering "Inbox" r)
                (should (stringp (jetpacs-node->canonical-json
                                  (glasspane-views--screen "Inbox" nil))))))
            ;; The drag list registers its resolution in the reader's
            ;; table (D-4) — and unregister sweeps exactly that.
            (let ((glasspane-views--reorder t)
                  (list-id (jetpacs-wire-id "views-reorder"
                                            (file-truename file))))
              (glasspane-views--set-rendering "Inbox" "list")
              (let ((json (jetpacs-node->canonical-json
                           (glasspane-views--screen "Inbox" nil))))
                (should (string-search "reorderable_list" json)))
              (let ((record (glasspane-org-reader-refile-lookup list-id)))
                (should record)
                (should (equal (plist-get record :file)
                               (file-truename file)))
                (should (= (length (plist-get record :keys)) 3)))
              (glasspane-views-unregister)
              (should-not (glasspane-org-reader-refile-lookup list-id))
              (should-not (gethash "views.open" jetpacs-action-handlers))
              (glasspane-views-register))
            ;; A broken query renders its feedback, a deleted view its
            ;; tombstone — both still whole screens ('accepted renders).
            (should (stringp (jetpacs-node->canonical-json
                              (glasspane-views--screen "Broken" nil))))
            (should (string-search "View deleted"
                                   (jetpacs-node->canonical-json
                                    (glasspane-views--screen "Ghost" nil))))
            ;; The sexp-valued Customize entry prints before parsing.
            (should (= (length (glasspane-views--items
                                (glasspane-views--get "Sexp")))
                       2))
            ;; The hub carries the cards and the literal form ids.
            (let ((json (jetpacs-node->canonical-json
                         (glasspane-views--hub-screen nil))))
              (dolist (id glasspane-views--form-ids)
                (should (string-search id json)))
              (should (string-search "Inbox" json)))))
      (ebp-org-cache-invalidate)
      (ebp-org-ref-tokens nil :set "views" :owner "glasspane")
      (dolist (buf (buffer-list))
        (let ((f (buffer-file-name buf)))
          (when (and f (string-prefix-p (file-name-as-directory
                                         (file-truename vault))
                                        (file-truename f)))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf))))
      (delete-directory vault t))))

;;;; G6 — search: glasspane-search.el

(ert-deftest glasspane-test-search-sexp-matrix ()
  "The builder's sexp output across every filter combination: each
non-empty build round-trips `ebp-org-parse-query' (the SPEC 23.2
vetter — the reason the text filter emits `heading', never the
allowlist-dropped `regexp'), and the three deadline range forms are
asserted against the interpreter itself through its documented
closure-accessor seam."
  (require 'glasspane-search)
  (cl-flet ((build (&rest overrides)
              (let ((glasspane-search--filter-todo
                     (plist-get overrides :todo))
                    (glasspane-search--filter-tags
                     (plist-get overrides :tags))
                    (glasspane-search--filter-text
                     (or (plist-get overrides :text) ""))
                    (glasspane-search--filter-priority
                     (plist-get overrides :priority))
                    (glasspane-search--filter-due
                     (plist-get overrides :due)))
                (glasspane-search--filter-query))))
    ;; Resting state builds the empty query — "Any" and nil alike.
    (should (equal (build) ""))
    (should (equal (build :todo "Any" :priority "Any" :due "Any") ""))
    ;; Each filter alone.
    (should (equal (build :todo "NEXT") "(todo \"NEXT\")"))
    (should (equal (build :todo "Done (any)") "(done)"))
    (should (equal (build :tags '("work")) "(tags \"work\")"))
    (should (equal (build :tags '("work" "home"))
                   "(and (tags \"work\") (tags \"home\"))"))
    (should (equal (build :priority "A") "(priority \"A\")"))
    ;; The three deadline range forms, spelled exactly as the
    ;; interpreter takes them (the G6 gate-entry check).
    (should (equal (build :due "Overdue") "(deadline :to -1)"))
    (should (equal (build :due "Today") "(deadline :on today)"))
    (should (equal (build :due "This week")
                   "(deadline :from today :to 7)"))
    ;; Text emits a trimmed heading clause — a title match — because
    ;; `regexp' is off the wire allowlist (ebp-org.el:828-836).
    (should (equal (build :text "  meeting notes ")
                   "(heading \"meeting notes\")"))
    ;; The full combination, in builder clause order.
    (should (equal (build :todo "TODO" :tags '("work" "deep")
                          :priority "B" :due "Today" :text "plan")
                   (concat "(and (todo \"TODO\") (tags \"work\")"
                           " (tags \"deep\") (priority \"B\")"
                           " (deadline :on today) (heading \"plan\"))")))
    ;; Every non-empty build survives the wire vetter; the regexp
    ;; spelling the v1 builder used would refuse.
    (dolist (q (list (build :todo "NEXT")
                     (build :todo "Done (any)")
                     (build :tags '("work" "home"))
                     (build :priority "A")
                     (build :due "Overdue")
                     (build :due "Today")
                     (build :due "This week")
                     (build :text "meeting notes")
                     (build :todo "TODO" :tags '("work")
                            :priority "B" :due "This week" :text "plan")))
      (should (consp (ebp-org-parse-query q))))
    (should-error (ebp-org-parse-query "(regexp \"meeting\")")
                  :type 'user-error)
    ;; The range forms against the interpreter: a closure accessor
    ;; serving only the planning question, over yesterday / today /
    ;; +5d / +30d deadline stamps.
    (cl-flet ((entry (deadline)
                (lambda (what &rest args)
                  (when (and (eq what 'planning)
                             (equal (car args) "DEADLINE"))
                    deadline))))
      (let* ((now (current-time))
             (yesterday (format-time-string
                         "<%Y-%m-%d>" (time-subtract now 86400)))
             (today (format-time-string "<%Y-%m-%d>" now))
             (soon (format-time-string
                    "<%Y-%m-%d>" (time-add now (* 5 86400))))
             (far (format-time-string
                   "<%Y-%m-%d>" (time-add now (* 30 86400))))
             (overdue (ebp-org-parse-query "(deadline :to -1)"))
             (due-today (ebp-org-parse-query "(deadline :on today)"))
             (week (ebp-org-parse-query
                    "(deadline :from today :to 7)")))
        (should (ebp-org-matches-p overdue (entry yesterday)))
        (should-not (ebp-org-matches-p overdue (entry today)))
        (should (ebp-org-matches-p due-today (entry today)))
        (should-not (ebp-org-matches-p due-today (entry yesterday)))
        (should (ebp-org-matches-p week (entry today)))
        (should (ebp-org-matches-p week (entry soon)))
        (should-not (ebp-org-matches-p week (entry yesterday)))
        (should-not (ebp-org-matches-p week (entry far)))
        ;; No stamp at all never matches a range form.
        (should-not (ebp-org-matches-p week (entry nil)))))))

(ert-deftest glasspane-test-search-screen-offline ()
  "The whole search flow with NO client: every handler answers a
SPEC 14.4 status straight from the table, the S2 defvars take their
single-writer updates, the S5 mint attaches resolvable tokens at
render, and the full screen builds + canonically serializes in every
arm — results, error card, and resting empty state — with no
absolute path on the wire."
  (require 'glasspane-search)
  (glasspane-search-register)
  (let* ((vault (make-temp-file "glasspane-search" t))
         (file (expand-file-name "notes.org" vault))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots nil)
         (org-tag-alist nil)
         (org-todo-keywords '((sequence "TODO" "|" "DONE")))
         (glasspane-search--query "")
         (glasspane-search--results nil)
         (glasspane-search--error nil)
         (glasspane-search--filter-todo nil)
         (glasspane-search--filter-tags nil)
         (glasspane-search--filter-text "")
         (glasspane-search--filter-priority nil)
         (glasspane-search--filter-due nil)
         (continuations nil))
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-flow-continue)
                   (lambda (fn) (push fn continuations) nil)))
          (with-temp-file file
            (insert "#+TITLE: Notes\n\n"
                    "* TODO Plan the meeting :work:\n"
                    "* DONE Old errand :errand:\n"
                    "* Reference\n"))
          (ebp-org-cache-invalidate)
          (cl-flet ((run (name args &optional params)
                      (let ((handler (gethash name jetpacs-action-handlers)))
                        (should handler)
                        (funcall handler args params))))
            ;; The whole table answers statuses on bare nil/nil input.
            (dolist (name glasspane-search--verbs)
              (should (memq (run name nil nil)
                            '(accepted stale rejected))))
            ;; org.search.run: results cached, the push deferred (D2).
            (let ((before (length continuations)))
              (should (eq (run "org.search.run" '(:value "todo:TODO"))
                          'accepted))
              (should (> (length continuations) before)))
            (should (equal glasspane-search--query "todo:TODO"))
            (should-not glasspane-search--error)
            (should (= (length glasspane-search--results) 1))
            ;; :value junk rejects without touching the cache.
            (should (eq (run "org.search.run" '(:value 42)) 'rejected))
            (should (equal glasspane-search--query "todo:TODO"))
            ;; S5: the render mint attaches a tap token that resolves
            ;; back to its heading — offline, tokens are Emacs state.
            (let* ((items (glasspane-ui--tokenize-tap
                           glasspane-search--results "search-results"))
                   (tok (alist-get 'token (car items))))
              (should (stringp tok))
              (should (equal (plist-get
                              (ebp-org-token-ref tok :owner "glasspane")
                              :headline)
                             "Plan the meeting")))
            ;; The results arm serializes; refs never cross the wire.
            (let ((json (jetpacs-node->canonical-json
                         (glasspane-search-screen nil))))
              (should (string-search "Query builder" json))
              (should (string-search "Plan the meeting" json))
              (should (string-search "heading.tap" json))
              (should-not (string-search (file-truename vault) json)))
            ;; update-filter: the S2 single-writer path — state lands
            ;; in the defvar and the equivalent query in the box.
            (should (eq (run "search.update-filter"
                             '(:field "todo" :value "TODO")
                             '(:surface "app:glasspane"))
                        'accepted))
            (should (equal glasspane-search--filter-todo "TODO"))
            (should (equal glasspane-search--query "(todo \"TODO\")"))
            (should (= (length glasspane-search--results) 1))
            ;; Tags dedupe on write (the multi-select distinct rule).
            (should (eq (run "search.update-filter"
                             '(:field "tags" :value ["work" "work"]))
                        'accepted))
            (should (equal glasspane-search--filter-tags '("work")))
            (should (= (length glasspane-search--results) 1))
            ;; Malformed filter traffic rejects, never signals.
            (should (eq (run "search.update-filter"
                             '(:field "bogus" :value "x"))
                        'rejected))
            (should (eq (run "search.update-filter"
                             '(:field "tags" :value 42))
                        'rejected))
            (should (eq (run "search.update-filter"
                             '(:field "text" :value ["no"]))
                        'rejected))
            ;; by-tag: the builder resets to exactly that tag and the
            ;; box shows the query the builder generated.
            (should (eq (run "search.by-tag" '(:tag "errand"))
                        'accepted))
            (should (equal glasspane-search--filter-tags '("errand")))
            (should-not glasspane-search--filter-todo)
            (should (equal glasspane-search--query "(tags \"errand\")"))
            (should (eq (run "search.by-tag" '(:tag "")) 'rejected))
            (should (eq (run "search.by-tag" nil) 'rejected))
            ;; A grammar refusal is an ERROR RENDER, not a rejection:
            ;; the card is the effect (S4), it never echoes the query,
            ;; and the screen still builds around it.
            (should (eq (run "org.search.run"
                             '(:value "(regexp \"x\")"))
                        'accepted))
            (should glasspane-search--error)
            (should-not glasspane-search--results)
            (should-not (string-search "(regexp"
                                       glasspane-search--error))
            (should (string-search "Query error"
                                   (jetpacs-node->canonical-json
                                    (glasspane-search-screen nil))))
            ;; clear-filters: back to resting; the deferred push rides
            ;; the draft-evicting :reset-input-ids.
            (should (eq (run "search.clear-filters" nil
                             '(:surface "app:glasspane"))
                        'accepted))
            (should (equal glasspane-search--query ""))
            (should-not glasspane-search--error)
            (should-not glasspane-search--filter-tags)
            (should (equal glasspane-search--filter-text ""))
            ;; The resting arm (empty state) serializes too.
            (should (string-search
                     "Search your notes"
                     (jetpacs-node->canonical-json
                      (glasspane-search-screen nil))))))
      (ebp-org-cache-invalidate)
      (dolist (buf (buffer-list))
        (let ((f (buffer-file-name buf)))
          (when (and f (string-prefix-p (file-name-as-directory
                                         (file-truename vault))
                                        (file-truename f)))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf))))
      (delete-directory vault t))))

;;;; G6 — table: glasspane-table.el

(defun glasspane-test--table-vault ()
  "A throwaway vault with the table/babel fixture; (VAULT . FILE)."
  (let* ((vault (make-temp-file "glasspane-table" t))
         (file (expand-file-name "table.org" vault)))
    (with-temp-file file
      (insert "* Data\n"
              "| a | b | sum |\n"
              "|---+---+-----|\n"
              "| 1 | 2 |   3 |\n"
              "#+TBLFM: $3=$1+$2\n"
              "\n"
              "* Lone\n"
              "| only |\n"
              "\n"
              "* Code\n"
              "#+begin_src glasspanetest\n"
              "ignored\n"
              "#+end_src\n"))
    (cons vault file)))

(defun glasspane-test--table-cleanup (vault)
  "Kill the vault's buffers, sweep the exposure records, drop the vault."
  (ebp-org-cache-invalidate)
  (jetpacs-buffer-forget-exposed)
  (dolist (buf (buffer-list))
    (let ((f (buffer-file-name buf)))
      (when (and f (string-prefix-p (file-name-as-directory
                                     (file-truename vault))
                                    (file-truename f)))
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf))))
  (delete-directory vault t))

(defun glasspane-test--table-pos (buf needle)
  "Position of NEEDLE's first char in BUF."
  (with-current-buffer buf
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (search-forward needle)
        (match-beginning 0)))))

(defun glasspane-test--table-disk (file)
  "FILE's current on-disk content."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(ert-deftest glasspane-test-table-mutate-edges ()
  "The mutation funnel over a real temp table: align+recalc through a
#+TBLFM line with `accepted'-grade durability (on disk, buffer clean),
formula-vs-value routing decided by `ebp-org-table-field-formula' (the
computed cell edits its formula, a plain cell its value — sanitized),
a killed row realigning from the table's start, the only row's kill
consuming the table without erroring, and the no-table refusal."
  (require 'glasspane-table)
  (let* ((fixture (glasspane-test--table-vault))
         (vault (car fixture))
         (file (cdr fixture)))
    (unwind-protect
        (let ((buf (find-file-noselect file)))
          (with-current-buffer buf
            (unless (derived-mode-p 'org-mode) (org-mode)))
          ;; Routing: the #+TBLFM-computed column names its entry, the
          ;; plain cell does not (the edit worker's fork).
          (with-current-buffer buf
            (org-with-wide-buffer
             (goto-char (glasspane-test--table-pos buf "3"))
             (should (equal (car (ebp-org-table-field-formula)) "$3"))
             (goto-char (+ 2 (glasspane-test--table-pos buf "| 1")))
             (should-not (ebp-org-table-field-formula))))
          ;; Value mutation: durable, realigned, recalculated (1+2
          ;; becomes 4+2 and the sum column follows).
          (glasspane-table--mutate
           buf (+ 2 (glasspane-test--table-pos buf "| 1"))
           (lambda () (org-table-get-field nil "4")))
          (should-not (buffer-modified-p buf))
          (should (string-match-p "| 4 | 2 | +6 |"
                                  (glasspane-test--table-disk file)))
          ;; The bridged edit worker, formula path: prefilled with the
          ;; stored RHS, stores the replacement, recalculates.  The
          ;; prefill is asserted OUTSIDE the stub — a `should' failing
          ;; inside the worker would be caught by its own error arm.
          (let (seen-initial)
            (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p)
                       (lambda () t))
                      ((symbol-function 'read-string)
                       (lambda (_prompt &optional initial &rest _)
                         (setq seen-initial initial)
                         "$1*$2"))
                      ((symbol-function 'jetpacs-shell-push)
                       (lambda (&rest _) nil))
                      ((symbol-function 'jetpacs-shell-notify)
                       (lambda (&rest _) nil)))
              (glasspane-table--edit-run
               buf (glasspane-test--table-pos buf "6") "app:glasspane"))
            (should (equal seen-initial "$1+$2")))
          (let ((disk (glasspane-test--table-disk file)))
            (should (string-search "$3=$1*$2" disk))
            (should (string-match-p "| 4 | 2 | +8 |" disk)))
          ;; The value path sanitizes: one line between pipes, always.
          (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p)
                     (lambda () t))
                    ((symbol-function 'read-string)
                     (lambda (&rest _) "x|y\nz"))
                    ((symbol-function 'jetpacs-shell-push)
                     (lambda (&rest _) nil))
                    ((symbol-function 'jetpacs-shell-notify)
                     (lambda (&rest _) nil)))
            (glasspane-table--edit-run
             buf (+ 2 (glasspane-test--table-pos buf "| a ")) "app:glasspane"))
          (should (string-search "x\\vert{}y z"
                                 (glasspane-test--table-disk file)))
          ;; The menu worker: deleting the data row leaves a smaller,
          ;; still-aligned table (realign from the table's start).
          ;; The header edit above widened column 1, so the needle is
          ;; the digit itself, not its old padding.
          (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p)
                     (lambda () t))
                    ((symbol-function 'completing-read)
                     (lambda (&rest _) "Delete row"))
                    ((symbol-function 'jetpacs-shell-push)
                     (lambda (&rest _) nil))
                    ((symbol-function 'jetpacs-shell-notify)
                     (lambda (&rest _) nil)))
            (glasspane-table--cell-menu-run
             buf (glasspane-test--table-pos buf "4 | 2") "app:glasspane"))
          (let ((disk (glasspane-test--table-disk file)))
            ;; The computed 8 lived only on the deleted row.
            (should-not (string-search "8" disk))
            (should (string-search "x\\vert{}y z" disk)))
          ;; Killing the ONLY row consumes the table: the funnel skips
          ;; the realign instead of erroring.
          (glasspane-table--mutate
           buf (+ 2 (glasspane-test--table-pos buf "| only"))
           #'org-table-kill-row)
          (should-not (string-search "| only |"
                                     (glasspane-test--table-disk file)))
          ;; No table at the heading: the funnel signals, mutating
          ;; nothing.
          (should-error (glasspane-table--mutate buf 1 #'ignore)))
      (glasspane-test--table-cleanup vault))))

(ert-deftest glasspane-test-table-headless-refusal ()
  "The D2 rewrite's sharp edges: every verb answers a status on junk,
unexposed addressing rejects (SPEC 23.1), the prompting verbs reject at
dispatch without a bridgeable session and their WORKERS notify instead
of raising a minibuffer prompt nobody attends (can-bridge nil -> notify
+ status, no wedge), the no-prompt add verbs are durable inside the
dispatch, babel times out and honors a declined confirm with a stub
language.  (The org sections this rung used to register moved to the
foundation with the §3 relocation — their coverage lives in
test/jetpacs-org-settings-test.el now.)"
  (require 'glasspane-table)
  (glasspane-table-register)
  (let* ((fixture (glasspane-test--table-vault))
         (vault (car fixture))
         (file (cdr fixture))
         (glasspane-babel-timeout 1)
         (notes nil)
         (continuations nil))
    (unwind-protect
        (let* ((buf (find-file-noselect file))
               (name (buffer-name buf)))
          (with-current-buffer buf
            (unless (derived-mode-p 'org-mode) (org-mode)))
          (cl-letf (((symbol-function 'jetpacs-shell-notify)
                     (lambda (text &rest _) (push text notes) nil))
                    ((symbol-function 'jetpacs-flow-continue)
                     (lambda (fn) (push fn continuations) nil)))
            (cl-flet ((run (verb args &optional params)
                        (let ((handler (gethash verb jetpacs-action-handlers)))
                          (should handler)
                          (funcall handler args params))))
              ;; The whole table answers statuses on bare nil/nil input.
              (dolist (verb glasspane-table--verbs)
                (should (memq (run verb nil nil)
                              '(accepted stale rejected))))
              ;; Well-formed but UNEXPOSED addressing rejects.
              (let ((anchor (glasspane-test--table-pos buf "| a ")))
                (should (eq (run "org.table.add-row"
                                 (list :buffer name :pos anchor))
                            'rejected))
                ;; Exposed: durable inside the dispatch — the new row is
                ;; on disk before `accepted' is answered; the repush is
                ;; a queued continuation, never inline.
                (jetpacs-buffer-expose name anchor "org.table.add-row")
                (jetpacs-buffer-expose name anchor "org.table.add-col")
                (let ((before (length continuations)))
                  (should (eq (run "org.table.add-row"
                                   (list :buffer name :pos anchor))
                              'accepted))
                  (should (= (length continuations) (1+ before))))
                ;; Four "|"-rows now: the Data table's three plus the
                ;; Lone table's one.
                (with-temp-buffer
                  (insert-file-contents file)
                  (goto-char (point-min))
                  (should (= 4 (count-matches "^| "))))
                ;; add-col appends at the right edge: the header line
                ;; gains a pipe.
                (should (eq (run "org.table.add-col"
                                 (list :buffer name :pos anchor))
                            'accepted))
                (with-temp-buffer
                  (insert-file-contents file)
                  (goto-char (point-min))
                  (search-forward "sum")
                  (should (= 5 (cl-count ?| (buffer-substring-no-properties
                                             (line-beginning-position)
                                             (line-end-position)))))))
              ;; The prompting verbs: exposure alone is not enough — no
              ;; connected+granted session, no flow, `rejected'.
              (let ((pos (+ 2 (glasspane-test--table-pos buf "| 1"))))
                (jetpacs-buffer-expose name pos "org.table.edit")
                (jetpacs-buffer-expose name pos "org.table.cell-menu")
                (should (eq (run "org.table.edit"
                                 (list :buffer name :pos pos))
                            'rejected))
                (should (eq (run "org.table.cell-menu"
                                 (list :buffer name :pos pos))
                            'rejected))
                ;; With a stubbed session the flow queues and the
                ;; handler answers on its strength; a JSON-float pos
                ;; coerces on the way through.
                (let ((flows nil))
                  (cl-letf (((symbol-function 'jetpacs-connected-p)
                             (lambda () t))
                            ((symbol-function 'jetpacs-granted-p)
                             (lambda (&rest _) t))
                            ((symbol-function 'jetpacs-flow-begin)
                             (lambda (surface fn)
                               (push (cons surface fn) flows) nil)))
                    (should (eq (run "org.table.edit"
                                     (list :buffer name :pos (float pos)))
                                'accepted))
                    (should (= (length flows) 1))))
                ;; The workers' headless refusal: notify, never a
                ;; minibuffer prompt (the stubs would signal).
                (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p)
                           (lambda () nil))
                          ((symbol-function 'read-string)
                           (lambda (&rest _)
                             (error "prompt raised headless")))
                          ((symbol-function 'completing-read)
                           (lambda (&rest _)
                             (error "prompt raised headless"))))
                  (setq notes nil)
                  (glasspane-table--edit-run buf pos "app:glasspane")
                  (should (string-search "attended session" (car notes)))
                  (glasspane-table--cell-menu-run buf pos "app:glasspane")
                  (should (string-search "attended session" (car notes)))))
              ;; Babel. Dispatch half: global confirm on, no dialog
              ;; grant — reject with the refusal notified.
              (let ((src (glasspane-test--table-pos buf "#+begin_src")))
                (jetpacs-buffer-expose name src "org.babel.execute")
                (let ((org-confirm-babel-evaluate t))
                  (setq notes nil)
                  (should (eq (run "org.babel.execute"
                                   (list :buffer name :pos src))
                              'rejected))
                  (should (string-search "attended session" (car notes)))
                  ;; Worker half: confirm due, bridge gone between
                  ;; dispatch and flow — notify, never prompt.
                  (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p)
                             (lambda () nil))
                            ((symbol-function 'yes-or-no-p)
                             (lambda (&rest _)
                               (error "prompt raised headless"))))
                    (setq notes nil)
                    (glasspane-table--babel-run buf src "app:glasspane")
                    (should (string-search "attended session" (car notes))))
                  ;; Declined confirm: `org-babel-confirm-evaluate'
                  ;; returns nil (it does not signal) — the run must
                  ;; stop on that, not evaluate anyway.
                  (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p)
                             (lambda () t))
                            ((symbol-function 'yes-or-no-p)
                             (lambda (&rest _) nil))
                            ((symbol-function 'org-babel-execute:glasspanetest)
                             (lambda (&rest _)
                               (error "evaluated after decline"))))
                    (setq notes nil)
                    (glasspane-table--babel-run buf src "app:glasspane")
                    (should (equal (car notes) "Evaluation declined")))
                  ;; Policy refusal, not a user decline: a nil
                  ;; `org-babel-check-confirm-evaluate' (a `:eval no' block)
                  ;; makes `org-babel-confirm-evaluate' answer nil with no
                  ;; prompt at all — the notification must say so.
                  (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p)
                             (lambda () t))
                            ((symbol-function 'org-babel-check-confirm-evaluate)
                             (lambda (&rest _) nil))
                            ((symbol-function 'yes-or-no-p)
                             (lambda (&rest _)
                               (error "prompt raised for a disabled block")))
                            ((symbol-function 'org-babel-execute:glasspanetest)
                             (lambda (&rest _)
                               (error "evaluated despite :eval no"))))
                    (setq notes nil)
                    (glasspane-table--babel-run buf src "app:glasspane")
                    (should (equal (car notes)
                                   "Evaluation disabled for this block"))))
                ;; Timeout: a stub language that outsleeps the budget —
                ;; the timer interrupts it and the failure is a notify,
                ;; not a wedge (no confirm due: option nil).
                (let ((org-confirm-babel-evaluate nil)
                      (ran nil))
                  (cl-letf (((symbol-function 'org-babel-execute:glasspanetest)
                             (lambda (&rest _)
                               (sleep-for 3)
                               (setq ran t)
                               "done")))
                    (setq notes nil)
                    (glasspane-table--babel-run buf src "app:glasspane")
                    (should-not ran)
                    (should (string-search "timed out" (car notes))))))
              ;; The unregister sweep, then restore for suite order.
              (glasspane-table-unregister)
              (dolist (verb glasspane-table--verbs)
                (should-not (gethash verb jetpacs-action-handlers)))
              (glasspane-table-register)
              (dolist (verb glasspane-table--verbs)
                (should (gethash verb jetpacs-action-handlers))))))
      (glasspane-test--table-cleanup vault))))

(ert-deftest glasspane-test-table-node-descriptors ()
  "The app-authored table node (gap #11): header/rule/data rows in
org's own convention, cell descriptors on the exposure route with no
path on the wire, and the loop closed — a descriptor's own args pass
the handler gate that will receive them."
  (require 'glasspane-table)
  (glasspane-table-register)
  (let* ((fixture (glasspane-test--table-vault))
         (vault (car fixture)))
    (unwind-protect
        (let* ((buf (find-file-noselect (cdr fixture)))
               (name (buffer-name buf))
               node)
          (with-current-buffer buf
            (unless (derived-mode-p 'org-mode) (org-mode))
            (jetpacs-buffer-forget-exposed name)
            (org-with-wide-buffer
             (goto-char (glasspane-test--table-pos buf "| a "))
             (setq node (glasspane-table-node (org-element-at-point)))))
          (should node)
          (should (equal (plist-get node :t) "table"))
          (let ((json (jetpacs-node->canonical-json node)))
            (should (string-search "org.table.edit" json))
            (should (string-search "org.table.cell-menu" json))
            (should (string-search "org.table.add-row" json))
            (should (string-search "org.table.add-col" json))
            ;; Exposure descriptors, never a baked path (S5/23.1).
            (should (string-search "\"buffer\"" json))
            (should-not (string-search "\"file\"" json))
            (should-not (string-search vault json)))
          (let ((rows (append (plist-get node :rows) nil)))
            (should (equal (mapcar (lambda (r) (plist-get r :kind)) rows)
                           '("header" "rule" "data")))
            ;; A data cell's own descriptor: exposed, and its args pass
            ;; the gate (the bridge half rejects without a session).
            (let* ((cells (append (plist-get (nth 2 rows) :cells) nil))
                   (args (plist-get (plist-get (car cells) :on_tap) :args)))
              (should (jetpacs-buffer-exposed-p
                       name (plist-get args :pos) "org.table.edit"))
              (should (eq (funcall (gethash "org.table.edit"
                                            jetpacs-action-handlers)
                                   args nil)
                          'rejected))))
          ;; The add affordances: exposed anchor, and the handler
          ;; mutates through it end to end.
          (let ((args (plist-get (plist-get node :on_add_row) :args))
                (continuations nil))
            (should (jetpacs-buffer-exposed-p
                     name (plist-get args :pos) "org.table.add-row"))
            (cl-letf (((symbol-function 'jetpacs-flow-continue)
                       (lambda (fn) (push fn continuations) nil)))
              (should (eq (funcall (gethash "org.table.add-row"
                                            jetpacs-action-handlers)
                                   args nil)
                          'accepted)))
            ;; Four "|"-rows: Data's two plus the appended one, plus
            ;; the Lone table's single row.
            (with-temp-buffer
              (insert-file-contents (cdr fixture))
              (goto-char (point-min))
              (should (= 4 (count-matches "^| "))))))
      (glasspane-test--table-cleanup vault))))

;;;; G7 — knowledge arms, notes half: glasspane-notes.el

(ert-deftest glasspane-test-notes-orgfree ()
  "The org-free notes logic: `--find-unlinked' skips occurrences
already inside an org link and matches case-insensitively within the
mention line; `--age-caption' formats the three ranges off the real
filesystem mtime; `--materialize-terms'' matched arm needs no vulpea
at all (it is what makes Link-it replayable offline)."
  (require 'glasspane-notes)
  ;; --materialize-terms: the matched arm is pure; the fallback arm
  ;; needs the note index and degrades to nil without it.
  (should (equal (glasspane-notes--materialize-terms "some-id" "Widget")
                 '("Widget")))
  (should-not (glasspane-notes--materialize-terms "some-id" ""))
  ;; --find-unlinked over a real org line: the linked occurrence is
  ;; skipped, the bare one (case-insensitive) is the hit, and the
  ;; match data lands on the text AS WRITTEN.
  (with-temp-buffer
    (org-mode)
    (insert "* Source\n"
            "Already [[id:x][Widget]] linked, then a bare widget here.\n"
            "Widget on the next line stays out of range.\n")
    (goto-char (point-min))
    (forward-line 1)
    (let ((term (glasspane-notes--find-unlinked '("Widget")
                                                (line-end-position))))
      (should (equal term "Widget"))
      (should (equal (match-string 0) "widget")))
    ;; Term order is specificity: the first term with a hit wins.
    (goto-char (point-min))
    (forward-line 1)
    (should (equal (glasspane-notes--find-unlinked '("zzz-never" "bare")
                                                   (line-end-position))
                   "bare"))
    ;; A term the line does not carry at all is a miss — the
    ;; file-changed arm's trigger.
    (goto-char (point-min))
    (forward-line 1)
    (should-not (glasspane-notes--find-unlinked '("nope")
                                                (line-end-position))))
  ;; --age-caption: days, months, years off a mocked mtime.
  (let ((file (make-temp-file "glasspane-age")))
    (unwind-protect
        (progn
          (set-file-times file (time-subtract nil (days-to-time 10)))
          (should (equal (glasspane-notes--age-caption file)
                         "modified 10 days ago"))
          (set-file-times file (time-subtract nil (days-to-time 100)))
          (should (equal (glasspane-notes--age-caption file)
                         "modified 3 months ago"))
          (set-file-times file (time-subtract nil (days-to-time 800)))
          (should (equal (glasspane-notes--age-caption file)
                         "modified 2 years ago")))
      (delete-file file))
    (should-not (glasspane-notes--age-caption
                 (concat file "-never-existed")))))

(ert-deftest glasspane-test-notes-guard-contract ()
  "With vulpea ABSENT — this harness's permanent condition — every
notes entry point degrades to nil and both verbs gate IN ORDER: a junk
shape rejects first, an unminted or swept token answers stale even
with the engine absent (it is a miss, not a refusal), and only a
RESOLVABLE token reaches the availability gate's rejected.  The
register/unregister pair sweeps its verbs, its three hook claims, and
the scan marks, and ends REGISTERED so suite order never matters."
  (require 'glasspane-notes)
  (should-not (featurep 'vulpea))
  (should-not (glasspane-notes-available-p))
  (should-not (glasspane-notes-stale-available-p))
  (should-not (glasspane-notes--matches "any"))
  (should-not (glasspane-notes--materialize-terms "id-sans-matched" nil))
  (should-not (glasspane-notes--stale-notes))
  (should-not (glasspane-notes-stale-section))
  (should-not (glasspane-notes-detail-nodes '(:file "/tmp/x.org" :pos 1)))
  (should-not (glasspane-notes-detail-toolbar '(:file "/tmp/x.org" :pos 1)))
  ;; The capf declines inside its own guard even mid-"[[".
  (with-temp-buffer
    (org-mode)
    (insert "[[Wid")
    (should-not (glasspane-notes--wikilink-capf)))
  (glasspane-notes-register)
  (unwind-protect
      (let ((mentions (gethash "notes.mentions" jetpacs-action-handlers))
            (materialize (gethash "link.materialize"
                                  jetpacs-action-handlers)))
        (should mentions)
        (should materialize)
        (should (memq #'glasspane-notes-detail-nodes
                      glasspane-ui-detail-nodes-functions))
        (should (memq #'glasspane-notes-detail-toolbar
                      glasspane-ui-detail-toolbar-functions))
        (should (memq #'glasspane-notes--setup-shadow
                      ebp-complete-shadow-setup-hook))
        ;; Junk shape rejects BEFORE the token lookup; an unminted
        ;; token is a MISS and answers stale even with vulpea absent —
        ;; borrowing the engine's rejected there would turn a swept
        ;; sheet's replay into a permanent receipt deletion.  Never a
        ;; signal, never a silent nil return.
        (should (eq (funcall mentions nil nil) 'rejected))
        (should (eq (funcall mentions '(:token 5) nil) 'rejected))
        (should (eq (funcall mentions '(:token "tok") nil) 'stale))
        (should (eq (funcall materialize nil nil) 'rejected))
        (should (eq (funcall materialize '(:token 5) nil) 'rejected))
        (should (eq (funcall materialize '(:token "tok") nil) 'stale))
        ;; Only a RESOLVABLE token reaches the availability gate — the
        ;; arm a fake token string can no longer see.
        (let* ((vault (make-temp-file "glasspane-notes-guard" t))
               (file (expand-file-name "note.org" vault))
               (org-directory vault)
               (org-agenda-files (list file))
               (ebp-org-roots nil))
          (unwind-protect
              (progn
                (with-temp-file file (insert "* Source note\n"))
                (ebp-org-cache-invalidate)
                (let ((tok (car (ebp-org-ref-tokens
                                 (list (list :id "NOTE-G" :file file :pos 1
                                             :headline "Source note"))
                                 :set "notes-guard" :owner "glasspane"))))
                  (should (stringp tok))
                  (should-not (glasspane-notes-available-p))
                  (should (eq (funcall mentions (list :token tok) nil)
                              'rejected))
                  (should (eq (funcall materialize (list :token tok) nil)
                              'rejected))))
            (ignore-errors (ebp-org-ref-tokens nil :set "notes-guard"
                                               :owner "glasspane"))
            (ebp-org-cache-invalidate)
            (delete-directory vault t)))
        ;; Unregister sweeps verbs, hooks, and scan marks.
        (puthash "leftover" 1 glasspane-notes--mentions-scans)
        (glasspane-notes-unregister)
        (should-not (gethash "notes.mentions" jetpacs-action-handlers))
        (should-not (gethash "link.materialize" jetpacs-action-handlers))
        (should-not (memq #'glasspane-notes-detail-nodes
                          glasspane-ui-detail-nodes-functions))
        (should-not (memq #'glasspane-notes-detail-toolbar
                          glasspane-ui-detail-toolbar-functions))
        (should-not (memq #'glasspane-notes--setup-shadow
                          ebp-complete-shadow-setup-hook))
        (should (zerop (hash-table-count glasspane-notes--mentions-scans))))
    (glasspane-notes-register)))

(ert-deftest glasspane-test-notes-materialize-edges ()
  "The link.materialize funnel over a real file with the availability
probe stubbed open (the vulpea-live arm is device territory; the
matched arm is org-free): a live edit-site token rewrites the first
UN-linked occurrence and answers accepted, a mention the file no
longer carries answers stale after its snackbar, a heading token
replayed here rejects on shape, junk and swept tokens keep their
classes, and a mint whose path fails the file policy degrades to nil
tokens instead of signaling.  notes.mentions marks the scan wanted
under the same stub and re-marks on re-tap."
  (require 'glasspane-notes)
  (glasspane-notes-register)
  (let* ((vault (make-temp-file "glasspane-notes" t))
         (file (expand-file-name "mentions.org" vault))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots nil)
         (notified nil)
         (materialize (gethash "link.materialize" jetpacs-action-handlers))
         (mentions (gethash "notes.mentions" jetpacs-action-handlers)))
    (unwind-protect
        (cl-letf (((symbol-function 'glasspane-notes-available-p)
                   (lambda () t))
                  ((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &rest _) (push text notified))))
          (with-temp-file file
            (insert "* Source note\n"
                    "Sees [[id:other][Widget]] and then Widget again.\n"))
          (ebp-org-cache-invalidate)
          ;; Success arm: the linked occurrence is skipped, the bare
          ;; one becomes a link, the save is synchronous.
          (let ((tok (car (ebp-org-ref-tokens
                           (list (list :file file :line 2
                                       :matched "Widget"
                                       :target-id "TARGET-1"))
                           :set "notes-test" :owner "glasspane"))))
            (should (eq (funcall materialize (list :token tok) nil)
                        'accepted))
            (should (cl-some (lambda (s) (string-search "Linked" s))
                             notified))
            (let ((text (with-temp-buffer
                          (insert-file-contents file)
                          (buffer-string))))
              (should (string-search "[[id:TARGET-1][Widget]]" text))
              (should (string-search "[[id:other][Widget]]" text))))
          ;; File-changed arm: every occurrence is a link now -> stale.
          (setq notified nil)
          (let ((tok (car (ebp-org-ref-tokens
                           (list (list :file file :line 2
                                       :matched "Widget"
                                       :target-id "TARGET-1"))
                           :set "notes-test" :owner "glasspane"))))
            (should (eq (funcall materialize (list :token tok) nil)
                        'stale))
            (should (cl-some (lambda (s) (string-search "file changed" s))
                             notified)))
          ;; A heading token replayed here: resolvable ref, wrong
          ;; SHAPE (no :line/:target-id) -> rejected.
          (let ((tok (car (ebp-org-ref-tokens
                           (list (list :file file :pos 1
                                       :headline "Source note"))
                           :set "notes-test" :owner "glasspane"))))
            (should (eq (funcall materialize (list :token tok) nil)
                        'rejected)))
          ;; Junk and swept keep their classes under the open probe.
          (should (eq (funcall materialize '(:token 5) nil) 'rejected))
          (should (eq (funcall materialize '(:token "never-minted") nil)
                      'stale))
          ;; A path outside the roots refuses at MINT time and the
          ;; helper degrades to nil tokens (untappable, not a crash).
          (should (equal (glasspane-notes--mint
                          (list (list :file "/definitely/not/here.org"))
                          "notes-test")
                         '(nil)))
          ;; A MIXED batch degrades per ref, and the set's replace
          ;; sweep still runs: the refused path costs its own token,
          ;; never the batch's — and never the previous render's
          ;; retirement, which an abort before the sweep would skip and
          ;; leave the old sheet's tokens live.
          (let* ((old (glasspane-notes--mint
                       (list (list :file file :pos 1)) "notes-mixed"))
                 (toks (glasspane-notes--mint
                        (list (list :file file :pos 1)
                              (list :file "/definitely/not/here.org" :pos 1))
                        "notes-mixed")))
            (should (= (length toks) 2))
            (should (stringp (nth 0 toks)))
            (should-not (nth 1 toks))
            (should-not (ebp-org-token-ref (car old) :owner "glasspane")))
          ;; --mint-sparse keeps positions: nils stay nil, the one
          ;; real ref gets a token that resolves in the app scope.
          (let ((toks (glasspane-notes--mint-sparse
                       (list nil (list :file file :pos 1) nil)
                       "notes-test")))
            (should (= (length toks) 3))
            (should-not (nth 0 toks))
            (should-not (nth 2 toks))
            (should (stringp (nth 1 toks)))
            (should (equal (plist-get (ebp-org-token-ref
                                       (nth 1 toks) :owner "glasspane")
                                      :file)
                           file)))
          ;; notes.mentions under the stubbed probe: a live heading
          ;; token carrying an :id marks the scan wanted (accepted),
          ;; and a re-tap bumps the count (the fresh-key re-run).
          (cl-letf (((symbol-function 'vulpea-note-unlinked-mentions-async)
                     (lambda (&rest _) nil)))
            (let ((tok (car (ebp-org-ref-tokens
                             (list (list :id "NOTE-9" :file file :pos 1
                                         :headline "Source note"))
                             :set "notes-test" :owner "glasspane"))))
              (should (eq (funcall mentions (list :token tok) nil)
                          'accepted))
              (should (= (gethash "NOTE-9" glasspane-notes--mentions-scans)
                         1))
              (should (eq (funcall mentions (list :token tok) nil)
                          'accepted))
              (should (= (gethash "NOTE-9" glasspane-notes--mentions-scans)
                         2)))))
      (clrhash glasspane-notes--mentions-scans)
      (ignore-errors (ebp-org-ref-tokens nil :set "notes-test"
                                         :owner "glasspane")
                     (ebp-org-ref-tokens nil :set "notes-mixed"
                                         :owner "glasspane"))
      (ebp-org-cache-invalidate)
      (dolist (buf (buffer-list))
        (let ((f (buffer-file-name buf)))
          (when (and f (string-prefix-p (file-name-as-directory
                                         (file-truename vault))
                                        (file-truename f)))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf))))
      (delete-directory vault t))))

(defun glasspane-test--actions (node)
  "Every ActionDescriptor in NODE's tree, depth first."
  (when (jetpacs-node-p node)
    (append (and (stringp (plist-get node :action)) (list node))
            (cl-loop for (_k v) on node by #'cddr
                     append (cond
                             ((jetpacs-node-p v)
                              (glasspane-test--actions v))
                             ((or (vectorp v) (proper-list-p v))
                              (cl-loop for x across (vconcat v)
                                       append (glasspane-test--actions x))))))))

(ert-deftest glasspane-test-notes-mention-card ()
  "The mention card's TWO tokens, built locally with the availability
probe stubbed open: the mint interleaves tap/edit-site refs pairwise,
so the card must take them in that order — a swapped destructure hands
`heading.tap' the edit-site ref and `link.materialize' a heading ref
its own shape gate then refuses.  The tokens are told apart by what
they RESOLVE to, and the Link-it action carries the ttl its queue
policy requires."
  (require 'glasspane-notes)
  (let* ((vault (make-temp-file "glasspane-mention" t))
         (file (expand-file-name "source.org" vault))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots nil)
         (mention (list :path file :line 2 :matched "Widget"
                        :context "and then Widget again.")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Source note\n"
                    "Sees [[id:other][Widget]] and then Widget again.\n"))
          (ebp-org-cache-invalidate)
          (cl-letf (((symbol-function 'glasspane-notes-available-p)
                     (lambda () t))
                    ((symbol-function 'glasspane-notes--backlinks)
                     (lambda (_id) nil))
                    ((symbol-function 'glasspane-notes--forward-links)
                     (lambda (_id) nil))
                    ((symbol-function 'glasspane-notes--mentions-state)
                     (lambda (_id) (cons 'ready (list mention)))))
            (let* ((nodes (glasspane-notes-detail-nodes
                           (list :id "NOTE-T9" :file file :pos 1)))
                   (actions (cl-loop for n in nodes
                                     append (glasspane-test--actions n)))
                   (taps (cl-remove-if-not
                          (lambda (a) (equal (plist-get a :action)
                                             "heading.tap"))
                          actions))
                   (links (cl-remove-if-not
                           (lambda (a) (equal (plist-get a :action)
                                              "link.materialize"))
                           actions)))
              (should (= (length taps) 1))
              (should (= (length links) 1))
              ;; The tap token is the MENTIONING note's heading ref...
              (let ((ref (ebp-org-token-ref
                          (plist-get (plist-get (car taps) :args) :token)
                          :owner "glasspane")))
                (should (equal (plist-get ref :file) file))
                (should (equal (plist-get ref :headline) "source.org"))
                (should-not (plist-get ref :line)))
              ;; ...and the Link-it token the EDIT SITE inside it.
              (let ((ref (ebp-org-token-ref
                          (plist-get (plist-get (car links) :args) :token)
                          :owner "glasspane")))
                (should (equal (plist-get ref :line) 2))
                (should (equal (plist-get ref :matched) "Widget"))
                (should (equal (plist-get ref :target-id) "NOTE-T9")))
              ;; A queued tap must carry its ttl (SPEC 14.1 / plan T4).
              (should (equal (plist-get (car links) :when_offline) "queue"))
              (should (equal (plist-get (car links) :ttl_s)
                             glasspane-notes--link-ttl-s)))))
      (ignore-errors (ebp-org-ref-tokens nil :set "notes-detail"
                                         :owner "glasspane"))
      (ebp-org-cache-invalidate)
      (dolist (buf (buffer-list))
        (let ((f (buffer-file-name buf)))
          (when (and f (string-prefix-p (file-name-as-directory
                                         (file-truename vault))
                                        (file-truename f)))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf))))
      (delete-directory vault t))))

;;;; G7 — knowledge arms: glasspane-srs.el

(ert-deftest glasspane-test-srs-layout ()
  "The pure card extraction/rendering stack over fixture buffers, org
core only: child-body regions, the three card-part layouts, part-node
rendering, drawer/link hiding in card content, and the cloze fill —
org-srs absent throughout (`cloze-collect' stubbed), every node set
round-tripping the canonical wire encoding."
  (require 'glasspane-srs)
  (cl-flet ((json-of (nodes)
              (jetpacs-node->canonical-json (apply #'jetpacs-column nodes))))
    ;; Explicit Front/Back children: both regions found, star-free.
    (with-temp-buffer
      (org-mode)
      (insert "* Capital cards\n"
              ":PROPERTIES:\n:ID: fixture-1\n:END:\n"
              "** Front\nWhat is the capital of France?\n"
              "** Back\nParis.\n")
      (goto-char (point-min))
      (let* ((child-re "^\\*\\{2\\}[ \t]")
             (front (glasspane-srs--child-body 1 "Front" child-re))
             (back (glasspane-srs--child-body 1 "Back" child-re)))
        (should front)
        (should (equal (buffer-substring-no-properties (car front)
                                                       (cdr front))
                       "What is the capital of France?\n"))
        (should back)
        (should (equal (buffer-substring-no-properties (car back)
                                                       (cdr back))
                       "Paris.\n"))
        (should-not (glasspane-srs--child-body 1 "Hint" child-re)))
      (let ((parts (glasspane-srs--card-parts 'back)))
        (should (eq (car (car parts)) 'region))
        (should (eq (car (cdr parts)) 'region))
        ;; Reviewing the front swaps question and answer.
        (should (equal (glasspane-srs--card-parts 'front)
                       (cons (cdr parts) (car parts))))))
    ;; Heading + body, no children: title question, body-region answer;
    ;; the answer body and a divider arrive only with the reveal.
    (with-temp-buffer
      (org-mode)
      (insert "* What is 2+2?\nFour.\n")
      (goto-char (point-min))
      (let* ((parts (glasspane-srs--card-parts 'back))
             (q (car parts)) (a (cdr parts)))
        (should (equal q (cons 'title "What is 2+2?")))
        (should (eq (car a) 'region))
        (let ((nodes (glasspane-srs--part-nodes q)))
          (should (= (length nodes) 1))
          (should (string-search "What is 2+2?" (json-of nodes))))
        (should-not (glasspane-srs--part-nodes '(title . "")))
        (should (glasspane-srs--part-nodes a))
        (let ((hidden (json-of (glasspane-srs--card-content
                                '(card back) nil)))
              (shown (json-of (glasspane-srs--card-content
                               '(card back) t))))
          (should (string-search "What is 2+2?" hidden))
          (should-not (string-search "Four." hidden))
          (should (string-search "Four." shown))
          (should (string-search "divider" shown)))))
    ;; Children without Front/Back (the Logseq layout):
    ;; title-and-region question, children answer.
    (with-temp-buffer
      (org-mode)
      (insert "* Prompt\nlead-in\n** First child\nanswer body\n")
      (goto-char (point-min))
      (let ((parts (glasspane-srs--card-parts 'back)))
        (should (eq (car (car parts)) 'title-and-region))
        (should (eq (car (cdr parts)) 'region))
        (let ((json (json-of (glasspane-srs--part-nodes (car parts)))))
          (should (string-search "Prompt" json))
          (should (string-search "lead-in" json)))))
    ;; Drawer + link hygiene: the SRSITEMS log never renders; a
    ;; descriptive link renders its description, never its target.
    (with-temp-buffer
      (org-mode)
      (insert "* Q\nSee [[https://example.com][the site]] for more.\n"
              ":SRSITEMS:\nsecret-log-row\n:END:\n")
      (goto-char (point-min))
      (let ((shown (json-of (glasspane-srs--card-content '(card back) t))))
        ;; The description survives (possibly split across rich-text
        ;; spans — segmentation is the renderer's), the target does not.
        (should (string-search "See " shown))
        (should (string-search "for more." shown))
        (should-not (string-search "https" shown))
        (should-not (string-search "example.com" shown))
        (should-not (string-search "secret-log-row" shown))
        (should-not (string-search "SRSITEMS" shown))))
    ;; Cloze: the reviewed blank hides until revealed; other clozes are
    ;; context; a hint shows bracketed.
    (with-temp-buffer
      (org-mode)
      (insert "* Geography\nParis is the capital of France.\n")
      (goto-char (point-min))
      (let* ((beg (save-excursion (goto-char (point-min))
                                  (search-forward "Paris")
                                  (match-beginning 0)))
             (end (+ beg 5)))
        (cl-letf (((symbol-function 'org-srs-item-cloze-collect)
                   (lambda (&rest _) (list (list 1 beg end "Paris" nil)))))
          (let ((hidden (json-of (glasspane-srs--cloze-content
                                  '(cloze 1) nil)))
                (shown (json-of (glasspane-srs--cloze-content
                                 '(cloze 1) t)))
                (other (json-of (glasspane-srs--cloze-content
                                 '(cloze 2) nil))))
            (should-not (string-search "Paris" hidden))
            (should (string-search "is the capital" hidden))
            (should (string-search "Paris" shown))
            (should (string-search "Paris" other))))
        (cl-letf (((symbol-function 'org-srs-item-cloze-collect)
                   (lambda (&rest _) (list (list 1 beg end "Paris" "city")))))
          (should (string-search "[city]"
                                 (json-of (glasspane-srs--cloze-content
                                           '(cloze 1) nil)))))))
    ;; An unresolvable item degrades to the couldn't-load caption —
    ;; org-srs absent, the marker probe is the quietly path.
    (should (string-search "load this card"
                           (json-of (glasspane-srs--item-nodes
                                     '((card back) "1" "nowhere") nil))))))

(ert-deftest glasspane-test-srs-rating-row ()
  "The rating rail over stubbed intervals: four buttons wired to
srs.rate by wire name, weight-matched interval captions above them,
and the caption row absent when the simulator has nothing to say."
  (require 'glasspane-srs)
  (let ((glasspane-srs--current '((card back) "1" "cards.org")))
    (cl-letf (((symbol-function 'glasspane-srs--intervals)
               (lambda () '(:again 60 :hard 36000 :good 259200
                            :easy 864000)))
              ((symbol-function 'org-srs-time-seconds-desc)
               (lambda (secs)
                 (if (>= secs 86400)
                     (list (/ secs 86400) :day (/ (% secs 86400) 3600) :hour)
                   (list (/ secs 3600) :hour)))))
      (let* ((controls (glasspane-srs--rating-controls))
             (json (jetpacs-node->canonical-json
                    (apply #'jetpacs-column controls))))
        (should (= (length controls) 2))
        (dolist (needle '("Again" "Hard" "Good" "Easy" "srs.rate"
                          "again" "hard" "good" "easy" "3d"))
          (should (string-search needle json)))))
    (cl-letf (((symbol-function 'glasspane-srs--intervals)
               (lambda () nil)))
      (should (= (length (glasspane-srs--rating-controls)) 1)))))

(ert-deftest glasspane-test-srs-handler-statuses ()
  "Every srs verb answers a SPEC 14.4 status over a stubbed engine:
write ok → `accepted', no item → `stale', bad rating/malformed →
`rejected' — and the G7 rework holds: an engine call that SIGNALS
answers `rejected' (dropping its own undo snapshot), never
`accepted'.  Registration is idempotent and sweeps clean; the detail
chip mints a token only while org-srs is available; the create flow
refuses headless without wedging."
  (require 'glasspane-srs)
  (glasspane-srs-register)
  (let* ((vault (make-temp-file "glasspane-srs" t))
         (file (expand-file-name "cards.org" vault))
         (ebp-org-roots nil)
         (org-directory vault)
         (glasspane-srs--available t)
         (glasspane-srs--active nil)
         (glasspane-srs--current nil)
         (glasspane-srs--revealed nil)
         (glasspane-srs--undo nil)
         (rated nil) (notified nil) (continuations nil)
         (marker nil) (item nil))
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &rest _) (push text notified)))
                  ((symbol-function 'jetpacs-toast) (lambda (&rest _) nil))
                  ((symbol-function 'jetpacs-shell-push)
                   (lambda (&rest _) nil))
                  ((symbol-function 'jetpacs-flow-continue)
                   (lambda (fn) (push fn continuations) nil))
                  ((symbol-function 'org-srs-item-marker)
                   (lambda (&rest _) marker))
                  ((symbol-function 'org-srs-review-rate)
                   (lambda (&rest args) (push args rated)))
                  ((symbol-function 'org-srs-review-pending-items)
                   (lambda (&rest _) (list item)))
                  ((symbol-function 'org-srs-review-postpone)
                   (lambda (&rest _) nil))
                  ((symbol-function 'org-srs-log-beginning-of-drawer)
                   #'ignore)
                  ((symbol-function 'org-srs-log-end-of-drawer) #'ignore)
                  ((symbol-function 'org-srs-log-hide-drawer) #'ignore))
          (with-temp-file file (insert "* Card one\nBody.\n"))
          (ebp-org-cache-invalidate)
          (setq marker (with-current-buffer (find-file-noselect file)
                         (org-with-wide-buffer (goto-char (point-min))
                                               (point-marker))))
          (setq item (list '(card back) "1"
                           (buffer-name (marker-buffer marker))))
          (cl-flet ((run (name args &optional params)
                      (let ((handler (gethash name jetpacs-action-handlers)))
                        (should handler)
                        (funcall handler args
                                 (or params '(:surface "app:glasspane"))))))
            ;; Registration is complete and idempotent.
            (dolist (name glasspane-srs--verbs)
              (should (gethash name jetpacs-action-handlers)))
            (glasspane-srs-register)
            (should (gethash "srs.rate" jetpacs-action-handlers))
            (should (memq #'glasspane-srs-detail-toolbar
                          glasspane-ui-detail-toolbar-functions))
            ;; Session gates before any session exists.
            (should (eq (run "srs.answer.show" nil) 'stale))
            (should (eq (run "srs.rate" '(:rating "good")) 'stale))
            (should (eq (run "srs.postpone" nil) 'stale))
            (should (eq (run "srs.suspend" nil) 'stale))
            (should (eq (run "srs.undo" nil) 'stale))
            (should (member "Nothing to undo" notified))
            ;; review.open defers a chrome push; start refuses without
            ;; the engine, arms the session with it.
            (should (eq (run "review.open" nil) 'accepted))
            (should (= (length continuations) 1))
            (setq glasspane-srs--available nil)
            (should (eq (run "srs.review.start" nil) 'rejected))
            (setq glasspane-srs--available t)
            (should (eq (run "srs.review.start" nil) 'accepted))
            (should glasspane-srs--active)
            (should (equal glasspane-srs--current item))
            ;; Reveal, and the pager mirror (malformed page rejects; the
            ;; mirror itself never re-pushes).
            (should (eq (run "srs.answer.show" nil) 'accepted))
            (should glasspane-srs--revealed)
            (should (eq (run "srs.answer.page" '(:value "x")) 'rejected))
            (should (eq (run "srs.answer.page" '(:value 0.0)) 'accepted))
            (should-not glasspane-srs--revealed)
            (should (eq (run "srs.answer.page" '(:value 1)) 'accepted))
            (should glasspane-srs--revealed)
            ;; rate: a bad name rejects untouched; a good one lands
            ;; through the engine and snapshots for undo.
            (should (eq (run "srs.rate" '(:rating "banana")) 'rejected))
            (should-not rated)
            (should (eq (run "srs.rate" '(:rating "good")) 'accepted))
            (should (= (length rated) 1))
            (should (eq (caar rated) :good))
            (should (= (length glasspane-srs--undo) 1))
            ;; The G7 rework: a signalling engine call answers
            ;; `rejected' and drops its own snapshot.
            (cl-letf (((symbol-function 'org-srs-review-rate)
                       (lambda (&rest _) (error "boom"))))
              (should (eq (run "srs.rate" '(:rating "good")) 'rejected)))
            (should (= (length glasspane-srs--undo) 1))
            (should (cl-some (lambda (s) (string-prefix-p "Review:" s))
                             notified))
            ;; undo restores from the snapshot and re-presents the card
            ;; answer-shown.
            (should (eq (run "srs.undo" nil) 'accepted))
            (should glasspane-srs--revealed)
            (should (equal glasspane-srs--current item))
            (should-not glasspane-srs--undo)
            ;; suspend comments the heading out — plain org, on disk.
            (should (eq (run "srs.suspend" nil) 'accepted))
            (should (string-search
                     "COMMENT"
                     (with-current-buffer (find-file-noselect file)
                       (buffer-substring-no-properties (point-min)
                                                       (point-max)))))
            ;; postpone rides the stub; quit clears the session.
            (should (eq (run "srs.postpone" nil) 'accepted))
            (should (eq (run "srs.quit" nil) 'accepted))
            (should-not glasspane-srs--active)
            (should-not glasspane-srs--current)
            ;; item.create: shape → token → availability gates, then
            ;; the deferred bridged flow with the headless refusal (no
            ;; wedge, no signal).
            (should (eq (run "srs.item.create" '(:token 5)) 'rejected))
            (should (eq (run "srs.item.create" '(:token "o0-junk"))
                        'stale))
            (let ((token (with-current-buffer (find-file-noselect file)
                           (org-with-wide-buffer
                            (goto-char (point-min))
                            (car (ebp-org-ref-tokens
                                  (list (ebp-org-ref-at-point))
                                  :set "t-srs" :owner "glasspane"))))))
              (setq glasspane-srs--available nil)
              (should (eq (run "srs.item.create" (list :token token))
                          'rejected))
              (setq glasspane-srs--available t)
              (setq continuations nil)
              (should (eq (run "srs.item.create" (list :token token))
                          'accepted))
              (should (= (length continuations) 1))
              (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p)
                         (lambda () nil)))
                (setq notified nil)
                (funcall (car continuations))
                (should notified)))
            ;; The detail chip joins the mint discipline: a token while
            ;; the engine is available, nothing without it.
            (let ((ref (with-current-buffer (find-file-noselect file)
                         (org-with-wide-buffer (goto-char (point-min))
                                               (ebp-org-ref-at-point)))))
              (let ((chips (glasspane-srs-detail-toolbar ref)))
                (should (= (length chips) 1))
                (should (string-search
                         "srs.item.create"
                         (jetpacs-node->canonical-json (car chips)))))
              (setq glasspane-srs--available nil)
              (should-not (glasspane-srs-detail-toolbar ref))
              (setq glasspane-srs--available t))
            ;; The sweep: unregister leaves no verb, chip, or section —
            ;; and no LIVE SESSION either, which is why the session is
            ;; re-armed first (srs.quit above cleared it).  A session
            ;; surviving the sweep would keep answering taps the app no
            ;; longer owns.
            (should (eq (run "srs.review.start" nil) 'accepted))
            (should glasspane-srs--active)
            (glasspane-srs-unregister)
            (dolist (name glasspane-srs--verbs)
              (should-not (gethash name jetpacs-action-handlers)))
            (should-not (memq #'glasspane-srs-detail-toolbar
                              glasspane-ui-detail-toolbar-functions))
            (should-not glasspane-srs--active)
            (should-not glasspane-srs--current)
            (should-not glasspane-srs--revealed)
            (should-not glasspane-srs--undo)
            (glasspane-srs-register)))
      (when-let* ((buf (find-buffer-visiting file)))
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf))
      (delete-directory vault t))))

;;;; G8 — fixtures: glasspane-demo.el

(require 'glasspane-demo)

(ert-deftest glasspane-test-demo-shift ()
  "The one-regexp timestamp shifter: zero days is the IDENTITY (the
corpus string comes back untouched), a real shift moves every
day-named date as one block with the day name recomputed in the C
locale, whatever follows the date (times, repeater cookies) rides
along unchanged, and the fixed-width stamp keeps table alignment
intact."
  (let ((content (cdr (assoc "trackers.org" glasspane-demo--org-files))))
    (should (equal (glasspane-demo--shift-timestamps content 0) content)))
  (let* ((sample (concat "DEADLINE: <2026-07-06 Mon>\n"
                         "SCHEDULED: <2026-07-05 Sun +1w>\n"
                         "CLOCK: [2026-07-03 Fri 08:20]--"
                         "[2026-07-03 Fri 08:34] =>  0:14\n"
                         "| [2026-06-29 Mon] |       40 |\n"))
         (shifted (glasspane-demo--shift-timestamps sample 2)))
    ;; Day names recomputed, not string-shifted: +2 from a Monday is a
    ;; Wednesday, and the C-locale binding inside the shifter makes
    ;; that spelling locale-proof.
    (should (string-search "DEADLINE: <2026-07-08 Wed>" shifted))
    ;; The repeater cookie rides untouched behind the moved date.
    (should (string-search "SCHEDULED: <2026-07-07 Tue +1w>" shifted))
    ;; Both halves of a clock range move; the times ride.
    (should (string-search
             "CLOCK: [2026-07-05 Sun 08:20]--[2026-07-05 Sun 08:34]"
             shifted))
    ;; Fixed width: a shifted table row still lines up.
    (should (= (length shifted) (length sample)))
    (should (string-search "| [2026-07-01 Wed] |       40 |" shifted))))

(ert-deftest glasspane-test-demo-seed ()
  "Corpus seeding over a throwaway vault: both write targets derive
from the roots defcustoms (never hardcoded paths — the G8 rule),
every written file re-reads as parseable org INSIDE the ebp-org
allowlist, the corpus's IDs are unique across files (id: links must
land on exactly one entry), and the anchor-dated stamp lands on the
day the seed ran."
  (let* ((vault (make-temp-file "glasspane-demo-vault" t))
         (org-directory (file-name-as-directory vault))
         (org-agenda-files nil)
         (ebp-org-roots nil)
         (ids nil))
    (unwind-protect
        (progn
          ;; The org-target derivation, both arms: nil roots fall
          ;; through to `org-directory'; an explicit head anchors to it.
          (should (equal (glasspane-demo--org-target) org-directory))
          (let ((ebp-org-roots '("vault")))
            (should (equal (glasspane-demo--org-target)
                           (file-name-as-directory
                            (expand-file-name "vault" org-directory)))))
          ;; The tour default derives from the Files landing dir, which
          ;; itself must lie inside `jetpacs-files-roots'.
          (should (equal glasspane-demo-directory
                         (expand-file-name "glasspane-demo"
                                           jetpacs-files-default-dir)))
          (let ((dir (glasspane-demo-setup-org)))
            (should (equal dir org-directory))
            (dolist (spec glasspane-demo--org-files)
              (let ((file (expand-file-name (car spec) dir)))
                (should (file-exists-p file))
                ;; Inside the allowlist: queries/mutations/mints admit it.
                (should (ebp-org-file-allowed-p file))
                (with-temp-buffer
                  (insert-file-contents file)
                  (let ((org-inhibit-startup t))
                    (delay-mode-hooks (org-mode)))
                  ;; A real parse: a corpus typo that breaks org
                  ;; structure fails here, not on the device.
                  (should (org-element-parse-buffer 'headline))
                  (goto-char (point-min))
                  (while (re-search-forward
                          "^[ \t]*:ID: +\\(\\S-+\\)[ \t]*$" nil t)
                    (push (match-string 1) ids)))))
            ;; Unique-ID lint across the whole corpus.
            (should (> (length ids) 0))
            (should (= (length ids)
                       (length (delete-dups (copy-sequence ids)))))
            ;; The authoring anchor IS the corpus's "today", so its
            ;; stamp must land on the seed day (C-locale day name).
            (should (string-search
                     (format "SCHEDULED: <%s>"
                             (let ((system-time-locale "C"))
                               (format-time-string "%Y-%m-%d %a")))
                     (with-temp-buffer
                       (insert-file-contents
                        (expand-file-name "inbox.org" dir))
                       (buffer-string))))))
      (delete-directory vault t))))

(ert-deftest glasspane-test-demo-handlers ()
  "The two demo verbs under the SPEC 14.4 contract: success writes
synchronously (durable before \\='accepted), notifies inline, and
setup-org's re-push rides the deferred continuation ONLY — zero
pushes inside the dispatch extent (D2); a REAL write failure (a file
squatting where the target directory must go) notifies, then answers
\\='rejected, scheduling nothing."
  (glasspane-demo-register)
  (let* ((tour (make-temp-file "glasspane-demo-tour" t))
         (vault (make-temp-file "glasspane-demo-vault" t))
         (blocker (make-temp-file "glasspane-demo-blocker"))
         (setup (gethash "demo.setup" jetpacs-action-handlers))
         (setup-org (gethash "demo.setup-org" jetpacs-action-handlers))
         (params (list :surface "app:glasspane"))
         (notified nil) (pushes 0) (continuations nil))
    (should setup)
    (should setup-org)
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &rest _) (push text notified)))
                  ((symbol-function 'jetpacs-shell-push)
                   (lambda (&rest _) (cl-incf pushes) nil))
                  ((symbol-function 'jetpacs-flow-continue)
                   (lambda (fn) (push fn continuations) nil)))
          ;; demo.setup, the success arm.
          (let ((glasspane-demo-directory tour))
            (should (eq (funcall setup nil params) 'accepted))
            (dolist (spec glasspane-demo--files)
              (should (file-exists-p
                       (expand-file-name (car spec) tour)))))
          (should (= (length notified) 1))
          (should (string-search "Demo files" (car notified)))
          ;; demo.setup-org, the success arm: notify inline, push
          ;; deferred — exactly one continuation, zero dispatch pushes.
          (let ((org-directory (file-name-as-directory vault))
                (org-agenda-files nil)
                (ebp-org-roots nil))
            (should (eq (funcall setup-org nil params) 'accepted))
            (should (file-exists-p
                     (expand-file-name "health.org" vault))))
          (should (= pushes 0))
          (should (= (length continuations) 1))
          (funcall (car continuations))
          (should (= pushes 1))
          ;; The failure arms: notify, then 'rejected, nothing scheduled.
          (setq notified nil continuations nil)
          (let ((glasspane-demo-directory
                 (expand-file-name "sub" blocker)))
            (should (eq (funcall setup nil params) 'rejected)))
          (should (= (length notified) 1))
          (should (string-search "failed" (car notified)))
          (let ((org-directory (expand-file-name "sub" blocker))
                (ebp-org-roots nil))
            (should (eq (funcall setup-org nil params) 'rejected)))
          (should (= (length notified) 2))
          (should (string-search "failed" (car notified)))
          (should-not continuations))
      (delete-file blocker)
      (delete-directory tour t)
      (delete-directory vault t))))

;;;; G8 — satellites: glasspane-ef.el (the theme-picker scaffold it
;;;; instantiates is foundation since the §3 step-3 promotion; the
;;;; scaffold-alone coverage moved with it, test/jetpacs-theme-picker-test.el)

(ert-deftest glasspane-test-ef-absent-paths ()
  "The DEFAULT suite path — ef-themes absent — is the real guard
coverage: `--available-p' reads only theme names, the not-installed
body keys its install tap on the `glasspane.packages.install'
handler-table entry (the srs install-body precedent), and ef.load
answers `rejected' for a malformed shape, an absent package, an
unknown theme, and a load that SIGNALS — never a swallowed
`accepted'."
  (require 'glasspane-ef)
  (glasspane-ef-register)
  (should (gethash "ef.load" jetpacs-action-handlers))
  ;; Availability is a pure read over the theme registry.
  (cl-letf (((symbol-function 'custom-available-themes)
             (lambda () '(modus-operandi tango))))
    (should-not (glasspane-ef--available-p)))
  (cl-letf (((symbol-function 'custom-available-themes)
             (lambda () (list 'modus-operandi (intern "ef-day")))))
    (should (glasspane-ef--available-p)))
  ;; The install tap tracks the packages rung's verb, both ways.  The
  ;; handler entry is restored by direct puthash so the claim records
  ;; are never touched.
  (let ((install (gethash "glasspane.packages.install"
                          jetpacs-action-handlers)))
    (should install)
    (let ((json (jetpacs-node->canonical-json (glasspane-ef--not-installed))))
      (should (string-search "\"action_label\":\"Install\"" json))
      (should (string-search "glasspane.packages.install" json)))
    (unwind-protect
        (progn
          (remhash "glasspane.packages.install" jetpacs-action-handlers)
          (let ((json (jetpacs-node->canonical-json
                       (glasspane-ef--not-installed))))
            (should-not (string-search "action_label" json))
            (should (string-search "isn't installed" json))))
      (puthash "glasspane.packages.install" install
               jetpacs-action-handlers)))
  ;; ef.load statuses.  Stubbing an unbound ef-themes function via
  ;; cl-letf restores its unboundness on exit (the srs org-srs-*
  ;; precedent).
  (let ((notified nil) (continuations nil) (loaded nil)
        (themes (list (intern "ef-day") (intern "ef-night"))))
    (cl-letf (((symbol-function 'jetpacs-shell-notify)
               (lambda (text &rest _) (push text notified)))
              ((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (push fn continuations) nil)))
      ;; Malformed shape: no :theme.
      (should (eq (glasspane-ef--on-load '(:other "x") nil) 'rejected))
      ;; Package absent.
      (cl-letf (((symbol-function 'glasspane-ef--ensure) (lambda () nil)))
        (should (eq (glasspane-ef--on-load '(:theme "ef-day") nil)
                    'rejected))
        (should (string-search "not installed" (car notified))))
      (cl-letf (((symbol-function 'glasspane-ef--ensure) (lambda () t))
                ((symbol-function 'glasspane-ef--themes)
                 (lambda () themes)))
        ;; Unknown theme -> rejected (the gate's named arm).
        (should (eq (glasspane-ef--on-load '(:theme "ef-nope") nil)
                    'rejected))
        (should (string-search "Unknown ef theme: ef-nope" (car notified)))
        ;; A load that lands -> accepted, refresh deferred.
        (cl-letf (((symbol-function 'ef-themes-load-theme)
                   (lambda (theme &optional _) (push theme loaded))))
          (should (eq (glasspane-ef--on-load '(:theme "ef-day") nil)
                      'accepted))
          (should (equal loaded (list (intern "ef-day"))))
          (should continuations))
        ;; A load that SIGNALS -> rejected, error labeled not swallowed.
        (cl-letf (((symbol-function 'ef-themes-load-theme)
                   (lambda (&rest _) (error "boom"))))
          (should (eq (glasspane-ef--on-load '(:theme "ef-day") nil)
                      'rejected))
          (should (string-search "Ef theme:" (car notified))))
        ;; The surprise loaders share the contract: absent fn ->
        ;; rejected; present -> accepted.
        (should (eq (glasspane-ef--on-random nil nil) 'rejected))
        (cl-letf (((symbol-function 'ef-themes-load-random)
                   (lambda (&optional _) nil)))
          (should (eq (glasspane-ef--on-random nil nil) 'accepted))))))
  ;; The satellite link: registered exactly once even after a
  ;; live-reload re-register, and swept by unregister.
  (should (= 1 (cl-count #'glasspane-ef--settings-link
                         jetpacs-settings-links :key #'cadr)))
  (glasspane-ef-register)
  (should (= 1 (cl-count #'glasspane-ef--settings-link
                         jetpacs-settings-links :key #'cadr)))
  (unwind-protect
      (progn
        (glasspane-ef-unregister)
        (should-not (cl-find #'glasspane-ef--settings-link
                             jetpacs-settings-links :key #'cadr)))
    ;; Suite order must never matter: leave ef registered.
    (glasspane-ef-register)))

(ert-deftest glasspane-test-settings-surface-scope ()
  "The D1 GLOBAL verbs, asserted at DISPATCH level — the only level
where SPEC 14.4's surface-scope gate exists.  Every verb here is
emitted from the Settings ROOT, a surface Glasspane does not own, so
without `:any-surface' the gate refuses the event before the handler
runs and the tap is silently dead on a device.  `jetpacs--dispatch'
resolves the owner from the action registry itself, so these are not
vacuous.  The owner-scoped rest is the control: a verb that only ever
fires from Glasspane's own surfaces must still be refused there."
  (require 'glasspane-ef)
  (glasspane-ef-register)
  (glasspane-ui-register)
  ;; `jetpacs--dispatch' takes (CLIENT PARAMS FN): the handler's args
  ;; ride INSIDE params, exactly as they arrive off the wire.
  (cl-flet ((dispatch (name args surface)
              (let ((handler (gethash name jetpacs-action-handlers)))
                (should handler)
                (jetpacs--dispatch
                 nil (list :action name :surface surface :args args)
                 handler))))
    (cl-letf (((symbol-function 'jetpacs-settings-save-variable)
               (lambda (_s v) v))
              ((symbol-function 'jetpacs-shell-notify) (lambda (&rest _) nil))
              ((symbol-function 'jetpacs-toast) (lambda (&rest _) nil))
              ((symbol-function 'jetpacs-flow-continue) (lambda (_fn) nil)))
      (let ((org-tag-alist '(("home" . ?h))))
        ;; The moved editors are OWNERLESS foundation verbs now (§3
        ;; step 2): gate-exempt by construction, no `:any-surface'
        ;; involved — the same dispatch proves they answer from a
        ;; surface nobody owns them on.
        (should (eq (dispatch "jetpacs.org.tags" '(:value ["work"])
                              "app:jetpacs.settings")
                    'accepted))
        (should (eq (dispatch "glasspane.settings.open" nil
                              "app:jetpacs.settings")
                    'accepted))
        (should (eq (dispatch "ef.show" nil "app:jetpacs.settings")
                    'accepted))
        ;; The control: an owner-scoped verb dies at the gate on a
        ;; foreign surface, which is what makes the four above bite.
        (should (eq (dispatch "journal.open" nil "app:jetpacs.settings")
                    'rejected)))))
  ;; The registry side of the same rule, verb by verb.  Only the
  ;; OPENERS stay global: their taps arrive before any guest screen
  ;; exists.
  (dolist (name '("glasspane.settings.open" "ef.show"))
    (should (gethash name jetpacs--any-surface-actions)))
  ;; The verbs emitted FROM the pushed screens dropped the flag (S4):
  ;; the opener's push registers a sanctioned guest, and the gate
  ;; delegates to `jetpacs-guest-delegation-function' instead — scoped
  ;; to the screen's lifetime, not granted forever.
  (dolist (name '("settings.agenda.edit" "settings.agenda.delete"
                  "glasspane.packages.install"))
    (should (gethash name jetpacs-action-handlers))
    (should-not (gethash name jetpacs--any-surface-actions)))
  ;; The moved family must NOT be in the any-surface set: ownerless
  ;; registration made the whole dance unnecessary (§3 step 2).
  (dolist (name '("jetpacs.org.tags" "jetpacs.org.todo.edit"
                  "jetpacs.org.todo.save" "jetpacs.org.todo.delete"
                  "jetpacs.org.workflow.open"))
    (should (gethash name jetpacs-action-handlers))
    (should-not (gethash name jetpacs--any-surface-actions)))
  ;; The dialog conclusions carry no surface at all, and the agenda verbs
  ;; fire from this owner's own screens: owner-scoped.
  (dolist (name '("settings.agenda.save" "agenda.save-custom"
                  "agenda.today" "agenda.select-date"
                  "agenda.set-month"))
    (should-not (gethash name jetpacs--any-surface-actions)))
  ;; GR-2's adapter emits its descriptors from the stable Files host, not a
  ;; Glasspane-owned surface.  The live-document/path guards in each handler
  ;; bound the global grant; without it D1 rejects the tap before those guards.
  (dolist (name '("heading.menu" "files.filter"
                  "files.toggle-refile" "heading.reorder"))
    (should (gethash name jetpacs--any-surface-actions)))
  ;; GR-4: native capture is global intake.  Shares are attributed by the
  ;; Companion, and the capture FAB is an app opinion emitted from this
  ;; downstream surface, so all three names must pass D1 here.
  (require 'jetpacs-org-capture)
  (let ((jetpacs-org-capture-enabled t))
    (jetpacs-org-capture-register))
  (dolist (name '("org.capture.show" "share.text" "org.capture.share"))
    (should (gethash name jetpacs--any-surface-actions)))
  (let ((jetpacs-org-capture--shared-text nil)
        (jetpacs-org-capture--shared-subject nil))
    (jetpacs--dispatch nil
                       '(:action "share.text"
                         :surface "app:something-else"
                         :args (:text "shared from elsewhere"))
                       (gethash "share.text" jetpacs-action-handlers))
    (should (equal jetpacs-org-capture--shared-text
                   "shared from elsewhere"))))

(ert-deftest glasspane-test-ef-option-nodes ()
  "Style section shapes.  Options unbound (the default suite path)
render caption cards; a bound option renders a switch whose `:checked'
re-seeds from the live variable (S2) and whose `:on-change' dispatches
`ef.option' (the watch-toggle rewrite) — and that handler honors the
SPEC 14.4 contract over a stubbed apply."
  (require 'glasspane-ef)
  (let* ((section (glasspane-ef--style-section))
         (json (jetpacs-node->canonical-json
                (apply #'jetpacs-column section))))
    (should (= (length section) 5))          ; header + 4 option cards
    (should (string-search "\"title\":\"Style\"" json))
    (should (string-search "not available" json))
    (should-not (string-search "\"t\":\"switch\"" json)))
  ;; One option bound: the switch card, checked mirroring the value.
  (cl-progv '(ef-themes-bold-constructs) '(t)
    (let ((json (jetpacs-node->canonical-json
                 (apply #'jetpacs-column (glasspane-ef--style-section)))))
      (should (string-search "\"t\":\"switch\"" json))
      (should (string-search "\"id\":\"ef-opt/ef-themes-bold-constructs\""
                             json))
      (should (string-search "\"checked\":true" json))
      (should (string-search "\"action\":\"ef.option\"" json))
      (should (string-search "ef-themes-bold-constructs" json))))
  (cl-progv '(ef-themes-bold-constructs) '(nil)
    (should (string-search "\"checked\":false"
                           (jetpacs-node->canonical-json
                            (apply #'jetpacs-column
                                   (glasspane-ef--style-section))))))
  ;; The ef.option handler: shape gates first, then availability, then
  ;; the apply verdict.  jetpacs-settings-apply is stubbed — the real
  ;; one persists through customize-save-variable.
  (let ((applied nil) (continuations nil) (notified nil))
    (cl-letf (((symbol-function 'jetpacs-settings-apply)
               (lambda (sym value _after) (push (cons sym value) applied) t))
              ((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (push fn continuations) nil))
              ((symbol-function 'jetpacs-shell-notify)
               (lambda (text &rest _) (push text notified))))
      (should (eq (glasspane-ef--on-option '(:name "no-such" :value t) nil)
                  'rejected))
      (should (eq (glasspane-ef--on-option
                   '(:name "ef-themes-bold-constructs" :value "yes") nil)
                  'rejected))
      ;; Known option, unbound symbol: the package left between render
      ;; and tap.
      (should (eq (glasspane-ef--on-option
                   '(:name "ef-themes-bold-constructs" :value t) nil)
                  'rejected))
      (should (string-search "not installed" (car notified)))
      (cl-progv '(ef-themes-bold-constructs) '(nil)
        (should (eq (glasspane-ef--on-option
                     '(:name "ef-themes-bold-constructs" :value t) nil)
                    'accepted))
        (should (equal (car applied) '(ef-themes-bold-constructs . t)))
        (should continuations)
        ;; :json-false decodes to elisp nil at the apply.
        (should (eq (glasspane-ef--on-option
                     '(:name "ef-themes-bold-constructs" :value :json-false)
                     nil)
                    'accepted))
        (should (equal (car applied) '(ef-themes-bold-constructs . nil))))
      ;; The apply refusing (schema mismatch) surfaces as rejected.
      (cl-letf (((symbol-function 'jetpacs-settings-apply)
                 (lambda (&rest _) nil)))
        (cl-progv '(ef-themes-bold-constructs) '(nil)
          (should (eq (glasspane-ef--on-option
                       '(:name "ef-themes-bold-constructs" :value t) nil)
                      'rejected)))))))

;;;; G8 — satellites: glasspane-gallery.el

(ert-deftest glasspane-test-gallery-trees ()
  "The gallery with NO client: the screen builds and canonically
serializes in every chart kind, the chart/canvas nodes carry the T3
member forms (ChartPoint series under `:name', the §16.5 border as a
wrapped universal attr), the Settings satellite link registers exactly
once and builds, and every handler answers a SPEC 14.4 status on good
and bad args — the kind enum rejecting junk, the level mirror clamping
float noise, the point tap landing its snackbar."
  (require 'glasspane-gallery)
  (glasspane-gallery-register)
  (let ((glasspane-gallery--kind "line")
        (glasspane-gallery--level 0.5)
        (continuations nil)
        (snack nil))
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-flow-continue)
                   (lambda (fn) (push fn continuations) nil))
                  ((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &rest _) (setq snack text) nil)))
          ;; Every kind renders and serializes; the chart carries the
          ;; selected kind, the series their T3 shapes, the gauge its
          ;; canvas, the slider its mirror-seeded value.
          (dolist (kind glasspane-gallery--chart-kinds)
            (setq glasspane-gallery--kind kind)
            (let ((json (jetpacs-node->canonical-json
                         (glasspane-gallery-screen nil))))
              (should (string-search "Widget Gallery" json))
              (should (string-search (format "\"kind\":\"%s\"" kind) json))
              (should (string-search "\"name\":\"alpha\"" json))
              (should (string-search "\"points\":" json))
              (should (string-search "\"canvas\"" json))
              (should (string-search "\"id\":\"gallery.level\"" json))
              (should (string-search "\"value\":0.5" json))
              ;; §16.5: the border rides as the universal-attr object,
              ;; never as an inline container option.
              (should (string-search
                       "\"border\":{\"color\":\"primary\",\"width\":2}"
                       json))))
          ;; The whole verb table answers statuses on bare nil/nil.
          (cl-flet ((run (name args &optional params)
                      (let ((handler (gethash name jetpacs-action-handlers)))
                        (should handler)
                        (funcall handler args params))))
            (dolist (name glasspane-gallery--verbs)
              (should (memq (run name nil nil) '(accepted stale rejected))))
            ;; demo.gallery: the push defers (D2), the reply is
            ;; accepted before the continuation ever runs.
            (let ((before (length continuations)))
              (should (eq (run "demo.gallery" nil '(:surface "app:x"))
                          'accepted))
              (should (> (length continuations) before)))
            ;; kind: the chips author the enum — junk rejects without
            ;; touching the mirror (no v1 silent "line" fallback).
            (should (eq (run "demo.gallery.kind" '(:kind "bar")) 'accepted))
            (should (equal glasspane-gallery--kind "bar"))
            (should (eq (run "demo.gallery.kind" '(:kind "pie")) 'rejected))
            (should (eq (run "demo.gallery.kind" '(:kind 7)) 'rejected))
            (should (equal glasspane-gallery--kind "bar"))
            ;; level: the mirror takes the commit and the re-render
            ;; re-seeds the slider from it; out-of-range clamps,
            ;; non-numbers reject.
            (should (eq (run "demo.gallery.level" '(:value 0.25)) 'accepted))
            (should (= glasspane-gallery--level 0.25))
            (should (eq (run "demo.gallery.level" '(:value 7)) 'accepted))
            (should (= glasspane-gallery--level 1.0))
            (should (eq (run "demo.gallery.level" '(:value "big")) 'rejected))
            (should (= glasspane-gallery--level 1.0))
            ;; point: the SPEC 17.5 injection (authored point in
            ;; :value, ordinal in :index) lands in the snackbar — the
            ;; notify IS the effect; a valueless tap rejects.
            (should (eq (run "demo.gallery.point"
                             '(:value (:x 1 :y 7) :index 1))
                        'accepted))
            (should (equal snack "point 1 = 7"))
            (should (eq (run "demo.gallery.point" '(:index 0)) 'rejected)))
          ;; The satellite link: registered exactly once even after a
          ;; live-reload re-register, and its row builds.
          (should (= (cl-count #'glasspane-gallery--settings-link
                               jetpacs-settings-links :key #'cadr)
                     1))
          (glasspane-gallery-register)
          (should (= (cl-count #'glasspane-gallery--settings-link
                               jetpacs-settings-links :key #'cadr)
                     1))
          (should (string-search "Widget Gallery"
                                 (jetpacs-node->canonical-json
                                  (glasspane-gallery--settings-link))))
          ;; The unregister sweep: no verb, no link survives.
          (glasspane-gallery-unregister)
          (dolist (name glasspane-gallery--verbs)
            (should-not (gethash name jetpacs-action-handlers)))
          (should-not (cl-find #'glasspane-gallery--settings-link
                               jetpacs-settings-links :key #'cadr)))
      ;; Suite order must never matter: leave the gallery registered.
      (glasspane-gallery-register))))

(ert-deftest glasspane-test-gallery-gauge-math ()
  "The app-local gauge (v1 core's jetpacs-gauge/-arc-points
transliterated onto the §17.5 canvas ops, T2): arc geometry, the
five-op stack, needle position at the poles, level clamping, and the
manually-offset label — pure, no client."
  (require 'glasspane-gallery)
  ;; 180°→0° over 44 segments = 45 points; screen y grows downward,
  ;; so both ends sit ON the baseline and the middle at cy - r.
  (let ((pts (glasspane-gallery--arc-points 120 116 95 180 0 44)))
    (should (= (length pts) 45))
    (should (< (abs (- (nth 0 (nth 0 pts)) 25)) 1e-6))
    (should (< (abs (- (nth 1 (nth 0 pts)) 116)) 1e-6))
    (should (< (abs (- (nth 0 (nth 22 pts)) 120)) 1e-6))
    (should (< (abs (- (nth 1 (nth 22 pts)) 21)) 1e-6))
    (should (< (abs (- (nth 0 (car (last pts))) 215)) 1e-6))
    (should (< (abs (- (nth 1 (car (last pts))) 116)) 1e-6)))
  ;; Mid level: the canvas node and its op stack, v1's strokes intact.
  (let* ((node (glasspane-gallery--gauge 0.5))
         (ops (plist-get node :ops)))
    (should (equal (plist-get node :t) "canvas"))
    (should (equal (plist-get node :width) 240))
    (should (equal (plist-get node :height) 132))
    (should (equal (mapcar (lambda (op) (plist-get op :op))
                           (append ops nil))
                   '("path" "path" "line" "circle" "text")))
    (should (equal (plist-get (aref ops 0) :stroke_width) 12))
    (should (= (length (plist-get (aref ops 0) :points)) 45))
    (should (equal (plist-get (aref ops 2) :width) 3))
    (should (equal (plist-get (aref ops 4) :text) "50%"))
    ;; The label is offset left of centre — the manual stand-in for
    ;; the align member §17.5 canvas text does not have.
    (should (< (plist-get (aref ops 4) :x) 120)))
  ;; The poles clamp: level ≥ 1 aims the needle right (end angle 0°),
  ;; level ≤ 0 left — never outside the arc.
  (let* ((ops (plist-get (glasspane-gallery--gauge 2.0) :ops))
         (needle (aref ops 2)))
    (should (equal (plist-get (aref ops 4) :text) "100%"))
    (should (< (abs (- (plist-get needle :x2) (+ 120 (* 95 0.9)))) 1e-6))
    (should (< (abs (- (plist-get needle :y2) 116)) 1e-6)))
  (let* ((ops (plist-get (glasspane-gallery--gauge -1) :ops))
         (needle (aref ops 2)))
    (should (equal (plist-get (aref ops 4) :text) "0%"))
    (should (< (abs (- (plist-get needle :x2) (- 120 (* 95 0.9)))) 1e-6)))
  ;; The gauge round-trips the canonical wire encoding on its own.
  (should (string-search "\"canvas\""
                         (jetpacs-node->canonical-json
                          (glasspane-gallery--gauge 0.25)))))

;;;; #26 — hub wiring

;; The rung punch-list #26 escalated: through G8 every ported surface
;; had a screen and an opening verb, and NOTHING on any surface emitted
;; one.  The gate below is the standing cure — it walks what the app
;; actually ships to the device and refuses to pass while an opener is
;; unreachable, so a future rung's new screen cannot land dead.

(defun glasspane-test--action-names (value)
  "Every `action' and `builtin' name reachable anywhere inside VALUE.
A generic walk, not a node walk: a descriptor hides in whatever member
its parent named (`:on_tap', a `:children' vector, a swipe object, a
menu item), and reachability is exactly the question of what a finger
can eventually dispatch — so the walk follows every cons it is given."
  (let (acc)
    (letrec ((walk (lambda (v)
                     (cond
                      ((vectorp v) (mapc walk v))
                      ((consp v)
                       (when (and (keywordp (car v)) (plistp v))
                         (dolist (key '(:action :builtin))
                           (let ((name (plist-get v key)))
                             (when (stringp name) (push name acc)))))
                       (funcall walk (car v))
                       (funcall walk (cdr v)))))))
      (funcall walk value))
    (delete-dups acc)))

(defun glasspane-test--settings-link-nodes ()
  "The built nodes of every Settings-root link THIS app registered.
`jetpacs-settings-links' entries are (ORDER BUILDER . OWNER)."
  (mapcar (lambda (entry) (funcall (cadr entry)))
          (cl-remove-if-not (lambda (entry)
                              (equal (cddr entry) glasspane-owner))
                            jetpacs-settings-links)))

(defconst glasspane-test--hub-verbs
  '("glasspane.home"
    "agenda.open"
    "tasks.open"
    "journal.open"
    "search.open"
    "views.hub"
    "review.open"
    "glasspane.settings.open")
  "THE RULE: every screen-opening verb the app owns must be
emitted by the home screen or its drawer.  These are the daily
surfaces; the two satellites below are the documented exception, and
`glasspane-test--non-opening-verbs' names everything that opens no
screen at all.  A verb added to the app without landing in one of the
three lists fails `glasspane-test-hub-verb-inventory', which is the
point: a new screen cannot ship unreachable.")

(defconst glasspane-test--satellite-verbs
  '("ef.show" "demo.gallery")
  "The satellite openers, whose entry point is a Settings-root link
rather than the hub (docs/CHROME-VOCABULARY.md: satellite screens live
in Settings links, not the drawer).  Registered by glasspane-ef and
glasspane-gallery at orders 81 and 84, beside the app's own 80.")

(defconst glasspane-test--non-opening-verbs
  '("agenda.nav" "agenda.save-custom" "agenda.select-date"
    "agenda.set-mode" "agenda.set-month" "agenda.today" "config.sync"
    "demo.gallery.kind" "demo.gallery.level" "demo.gallery.point"
    "demo.setup" "demo.setup-org" "detail.planning.edit" "detail.save"
    "detail.toggle-read" "ef.load" "ef.mirror" "ef.option" "ef.random"
    "ef.random-dark" "ef.random-light" "files.filter"
    "files.properties.save" "files.properties.show"
    "files.toggle-refile" "glasspane.packages.install"
    "heading.add-note" "heading.clock-in" "heading.delete"
    "heading.duplicate" "heading.menu" "heading.priority"
    "heading.prop-add" "heading.prop-set" "heading.props.show"
    "heading.refile" "heading.reorder" "heading.schedule"
    "heading.tags" "heading.tap" "heading.todo-cycle"
    "heading.todo-set" "journal.capture" "journal.goto" "journal.nav"
    "journal.today" "link.materialize" "notes.mentions"
    "org.babel.execute" "org.link.open"
    "org.search.run" "org.table.add-col" "org.table.add-row"
    "org.table.cell-menu" "org.table.edit" "search.by-tag"
    "search.clear-filters" "search.update-filter"
    "settings.agenda.delete" "settings.agenda.edit"
    "settings.agenda.save"
    "srs.answer.page" "srs.answer.show" "srs.item.create"
    "srs.postpone" "srs.quit" "srs.rate" "srs.review.start"
    "srs.suspend" "srs.undo" "tasks.filter" "views.cal.select-date"
    "views.cal.set-month" "views.delete" "views.open"
    "views.rendering" "views.reorder" "views.save")
  "Every verb that opens NO screen of its own, and therefore needs no
hub entry: the in-screen controls (filters, navigation, ratings, cell
and heading mutations), the dialog-fired saves, the M-x-only seeders
(demo.setup*), and the drill-ins reached FROM a screen the hub opens
(views.open from the views hub, heading.tap from every card).
Classification only — the list exists so the inventory below is total.")

(ert-deftest glasspane-test-hub-reaches-every-opener ()
  "The hub is REACHABILITY: build the home screen and walk it.
Every verb in `glasspane-test--hub-verbs' must be dispatchable from
the screen the chrome root registers — body row, drawer row or FAB —
and must be a verb the app really registered (a typo in a descriptor
is a dead row, which is the defect this rung exists to end).  The
drawer is the canonical navigation, so it carries the whole set on its
own; the body carries every destination in the table."
  (let* ((screen (glasspane-ui-home-screen nil))
         (reachable (glasspane-test--action-names screen))
         (drawer (glasspane-test--action-names (plist-get screen :drawer)))
         (body (glasspane-test--action-names (plist-get screen :body))))
    (dolist (verb glasspane-test--hub-verbs)
      (should (member verb reachable))
      (should (gethash verb jetpacs-action-handlers))
      (should (equal (jetpacs--owner-of "action" verb) glasspane-owner))
      (should (member verb drawer)))
    ;; Capture is deliberately the exception to app ownership: this app
    ;; chooses three placements, while the native Org engine owns the one
    ;; global command they all emit.
    (should (member "org.capture.show" reachable))
    (should (member "org.capture.show" drawer))
    (should (equal (jetpacs--owner-of "action" "org.capture.show")
                   "org-mode"))
    (should (gethash "org.capture.show" jetpacs--any-surface-actions))
    (dolist (dest glasspane-ui-destinations)
      (should (member (plist-get dest :verb) body)))
    ;; The FAB is the screen's one creation act, and it names the same
    ;; verb the Capture row does — one command, three projections.
    (should (equal (plist-get (plist-get (plist-get screen :fab) :on_tap)
                              :action)
                   "org.capture.show")))
  ;; The satellites keep the vocabulary's route: a Settings-root link.
  (let ((links (glasspane-test--action-names
                (glasspane-test--settings-link-nodes))))
    (dolist (verb glasspane-test--satellite-verbs)
      (should (member verb links))
      (should (gethash verb jetpacs-action-handlers)))))

(ert-deftest glasspane-test-hub-drawer-carries-the-other-apps ()
  "The org reader registers NO opening verb — it claims the files
editor body seam, so a `.org' tapped in the base Files app IS its
entry — which is why the drawer ends in `jetpacs-launcher-rows', the
base's own drawer convention, excluding this app's own surface.  The
launcher is absent from the batch image (present on device,
device/init.el:44), so the guarded arm must also build to a drawer
with no app rows at all."
  (should-not (member "jetpacs.launcher.open"
                      (glasspane-test--action-names
                       (glasspane-ui--home-drawer))))
  (let (excluded)
    (cl-letf (((symbol-function 'jetpacs-launcher-rows)
               (lambda (&optional exclude)
                 (setq excluded exclude)
                 (list (jetpacs-chrome-row
                        "Files"
                        :icon "folder"
                        :on-tap (jetpacs-action
                                 "jetpacs.launcher.open"
                                 :args '(:surface "app:jetpacs.files"))
                        :key "lr-files")))))
      (let ((drawer (glasspane-ui--home-drawer)))
        (should (member "jetpacs.launcher.open"
                        (glasspane-test--action-names drawer)))
        (should (stringp (jetpacs-node->canonical-json drawer)))))
    (should (equal excluded (jetpacs-shell-surface-for glasspane-owner)))))

(ert-deftest glasspane-test-hub-verb-inventory ()
  "THE TRIPWIRE: every verb glasspane registers is classified as a hub
opener, a satellite opener, or no opener at all.  A new verb that
nobody wired shows up as an unclassified name and fails here — the
mechanical half of the rule stated on `glasspane-test--hub-verbs' —
and a retired verb left in a list fails the other way."
  (let ((owned nil)
        (pinned (append glasspane-test--hub-verbs
                        glasspane-test--satellite-verbs
                        glasspane-test--non-opening-verbs)))
    (maphash (lambda (name _fn)
               (when (equal (jetpacs--owner-of "action" name) glasspane-owner)
                 (push name owned)))
             jetpacs-action-handlers)
    ;; Named both ways: the failure message says WHICH verb drifted.
    (should-not (cl-set-difference owned pinned :test #'equal))
    (should-not (cl-set-difference pinned owned :test #'equal))
    (should (= (length pinned) (length (delete-dups (copy-sequence pinned)))))))

(ert-deftest glasspane-test-hub-serializes ()
  "The hub clears the wire bar the whole app clears: a scaffold with
the three chrome slots filled, inside the SPEC 16.2 `app' profile,
with SPEC 16.1-unique ids, round-tripping the canonical encoding.  The
body and drawer copies of one destination keep DISTINCT SPEC 16.5
keys — they ship in the same document, and a shared key would make the
reconciler treat two rows as one."
  (let* ((screen (glasspane-ui-home-screen nil))
         (json (jetpacs-node->canonical-json screen))
         (ids (jetpacs-collect-node-ids screen nil)))
    (should (equal (plist-get screen :t) "scaffold"))
    (should (plist-get screen :body))
    (should (plist-get screen :drawer))
    (should (plist-get screen :fab))
    (should (jetpacs-check-profile screen 'app))
    (should (equal ids (delete-dups (copy-sequence ids))))
    (should (stringp json))
    (should (string-search "\"agenda.open\"" json))
    (should (string-search "Saved views" json))
    (should (string-search "\"hub-agenda\"" json))
    (should (string-search "\"drawer-agenda\"" json))))

(provide 'glasspane-test)
;;; glasspane-test.el ends here
