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
  "Unregistration leaves no verb, no registry entry — and is undone by
`glasspane-register' (the live-reload path), which this test restores
so suite order never matters."
  (unwind-protect
      (progn
        (glasspane-unregister)
        (should-not (gethash "glasspane.home" jetpacs-action-handlers))
        (should-not (assoc glasspane-owner jetpacs-apps--registry)))
    (glasspane-register))
  (should (gethash "glasspane.home" jetpacs-action-handlers)))

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

(provide 'glasspane-test)
;;; glasspane-test.el ends here
