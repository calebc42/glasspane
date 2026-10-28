;;; glasspane-fab-test.el --- The state-aware FAB -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Builders per screen and clock state, the degrade path, the heading,
;; list and file actions against real Org files, the countdown's reminder,
;; and the outline FAB hook.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'glasspane)

(glasspane-register)  ; `require' only loads

(defmacro glasspane-fab-test--advertised (types &rest body)
  "Run BODY with exactly node TYPES advertised (all others too when t)."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'jetpacs-node-advertised-p)
              (lambda (type &rest _) (or (eq ,types t) (member type ,types)))))
     ,@body))

(defun glasspane-fab-test--labels (fab)
  "FAB's menu labels."
  (mapcar (lambda (item) (plist-get item :label))
          (append (plist-get fab :menu) nil)))

(defun glasspane-fab-test--action (fab label)
  "The action of FAB's menu item LABEL."
  (plist-get (cl-find label (append (plist-get fab :menu) nil)
                      :key (lambda (i) (plist-get i :label)) :test #'equal)
             :on_tap))

(ert-deftest glasspane-fab-test-list-fab-primary-and-menu ()
  "Lists: Capture, a quick task carrying the day and Area, the templates."
  (let ((org-capture-templates '(("t" "Task" entry (file "/tmp/x.org") "* TODO %?")
                                 ("j" "Journal" entry (file "/tmp/j.org") "* %?"))))
    (cl-letf (((symbol-function 'org-clocking-p) (lambda () nil)))
      (glasspane-fab-test--advertised t
        (let ((fab (glasspane-fab-list :date "2026-10-29" :area "Home")))
          (should (equal (plist-get fab :t) "material3.fab"))
          (should (equal (plist-get fab :label) "Capture"))
          (should (eq (plist-get fab :collapse_on_scroll) t))
          (should (equal (glasspane-fab-test--labels fab) '("New task" "Task" "Journal")))
          (should (equal (plist-get (glasspane-fab-test--action fab "New task") :args)
                         '(:date "2026-10-29" :area "Home")))
          (should (equal (plist-get (glasspane-fab-test--action fab "Journal") :args)
                         '(:template "j")))
          (should (jetpacs-check-profile fab 'app)))))))

(ert-deftest glasspane-fab-test-clock-makes-the-primary-clock-out ()
  "While a clock runs every FAB's primary is Clock out with the task."
  (let ((org-clock-current-task "Write the report for the quarterly review"))
    (cl-letf (((symbol-function 'org-clocking-p) (lambda () t)))
      (glasspane-fab-test--advertised t
        (dolist (fab (list (glasspane-fab-list)
                           (glasspane-fab-heading "tok")
                           (glasspane-fab-outline "/v/a.org")))
          (should (string-prefix-p "Clock out" (plist-get fab :label)))
          (should (equal (plist-get fab :content_description)
                         "Clock out of Write the report for the quarterly review"))
          (should (equal (plist-get (plist-get fab :on_tap) :action) "org.clock.out"))
          (should (equal (plist-get fab :color) "tertiary")))
        ;; Lists name the task; the heading page keeps the FAB narrow so it
        ;; sits beside the pane's bottom rows (its band shows the clock).
        (should (string-prefix-p "Clock out · Write the report"
                                 (plist-get (glasspane-fab-list) :label)))
        (should (equal (plist-get (glasspane-fab-heading "tok") :label) "Clock out"))
        (should (member "Under clocked task"
                        (glasspane-fab-test--labels (glasspane-fab-list))))
        (should (member "Cancel clock"
                        (glasspane-fab-test--labels (glasspane-fab-heading "tok"))))))))

(ert-deftest glasspane-fab-test-heading-fab ()
  "A heading page offers Clock in and its structure, time and extras."
  (cl-letf (((symbol-function 'org-clocking-p) (lambda () nil)))
    (glasspane-fab-test--advertised t
      (let* ((fab (glasspane-fab-heading "tok" '(:effort "0:45")))
             (labels (glasspane-fab-test--labels fab)))
        (should (equal (plist-get fab :label) "Clock in"))
        (should (equal (plist-get (plist-get fab :on_tap) :args) '(:token "tok")))
        (should (equal labels '("Add sub-task" "Countdown 0:45" "Set effort…"
                                "Structure…" "More…")))
        (should (<= (length labels) 7))
        (should (equal (plist-get (glasspane-fab-test--action fab "More…") :args)
                       '(:token "tok" :group "more")))
        (let ((groups (glasspane-fab--heading-groups "tok")))
          (should (equal (mapcar #'car (cdr (assoc "structure" groups)))
                         '("Add sub-heading" "Add sibling task" "Move up" "Move down"
                           "Promote" "Demote")))
          (should (equal (mapcar #'car (cdr (assoc "more" groups)))
                         '("Clone with time shift…" "Run code blocks" "Sort children…"
                           "Update [/] cookies" "Toggle ARCHIVE tag")))
          (should (plist-get (nth 2 (assoc "Run code blocks" (cdr (assoc "more" groups))))
                             :confirm)))
        (should (jetpacs-check-profile fab 'app))
        (should-not (glasspane-fab-heading nil))))))

(ert-deftest glasspane-fab-test-group-sheet ()
  "Structure… and More… open a sheet of their actions; junk groups reject."
  (glasspane-fab-test--with-file "* Top\n"
    (let (shown)
      (cl-letf (((symbol-function 'jetpacs-client) (lambda () 'fake))
                ((symbol-function 'jetpacs-flow-continue) (lambda (fn) (funcall fn)))
                ((symbol-function 'jetpacs-dialog-slot-show)
                 (lambda (id spec &rest keys)
                   (jetpacs-check-profile spec 'dialog)
                   (setq shown (list id spec (plist-get keys :style))))))
        (should (eq (glasspane-fab--on-group (list :token token :group "more") nil)
                    'accepted))
        (should (equal (car shown) "gp-fab-group-more"))
        (should (equal (nth 2 shown) "sheet"))
        (should (string-search "Toggle ARCHIVE tag"
                               (jetpacs-node->canonical-json (nth 1 shown))))
        (should (eq (glasspane-fab--on-group (list :token token :group "nope") nil)
                    'rejected))
        (should (eq (glasspane-fab--on-group '(:token "expired" :group "more") nil)
                    'stale))))))

(ert-deftest glasspane-fab-test-degrades-without-the-node ()
  "No material3.fab: the FAB menu; no menu either: the capture button."
  (cl-letf (((symbol-function 'org-clocking-p) (lambda () nil)))
    (glasspane-fab-test--advertised '("material3.fab_menu")
      (let ((fab (glasspane-fab-list)))
        (should (equal (plist-get fab :t) "material3.fab_menu"))
        (should (equal (plist-get (aref (plist-get fab :items) 0) :label) "Capture"))))
    (glasspane-fab-test--advertised '()
      (let ((fab (glasspane-fab-list)))
        (should (equal (plist-get fab :t) "icon_button"))
        (should (equal (plist-get (plist-get fab :on_tap) :action) "org.capture.show"))))))

(defmacro glasspane-fab-test--with-file (text &rest body)
  "Run BODY with `file' an Org file holding TEXT and `ref'/`token' its first heading."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "gp-fab" t))
          (file (expand-file-name "a.org" dir))
          (org-directory dir)
          (ebp-org-roots (list dir))
          (org-agenda-files (list file)))
     (unwind-protect
         (progn
           (write-region ,text nil file nil 'silent)
           (ebp-org-cache-invalidate)
           (let* ((ref (with-current-buffer (find-file-noselect file)
                         (goto-char (point-min))
                         (ebp-org-ref-at-point)))
                  (token (car (ebp-org-ref-tokens (list ref) :set "fab-test"
                                                  :owner "glasspane"))))
             (ignore token)
             (cl-letf (((symbol-function 'jetpacs-app-defer-refresh) #'ignore)
                       ((symbol-function 'jetpacs-shell-notify) #'ignore)
                       ((symbol-function 'jetpacs-org-save-policy)
                        (lambda (&optional b) (with-current-buffer (or b (current-buffer))
                                                (save-buffer)))))
               ,@body)))
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b)
                    (string-prefix-p dir (buffer-file-name b)))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory dir t))))

(defun glasspane-fab-test--text (file)
  "FILE's buffer text."
  (with-current-buffer (find-file-noselect file) (buffer-string)))

(ert-deftest glasspane-fab-test-heading-actions-edit-the-file ()
  "Move, cookies, ARCHIVE and Effort through the verbs; statuses bounded."
  (glasspane-fab-test--with-file
      "* Top [/]\n** TODO A\n** DONE B\n* Second\n"
    (let ((run (lambda (verb args)
                 (funcall (gethash verb jetpacs-action-handlers) args nil)))
          (fresh (lambda ()
                   ;; An edit to the headline retires its token; the app's
                   ;; refresh re-mints, as this does.
                   (car (ebp-org-ref-tokens
                         (list (with-current-buffer (find-file-noselect file)
                                 (goto-char (point-min))
                                 (ebp-org-ref-at-point)))
                         :set "fab-test" :owner "glasspane")))))
      (should (eq (funcall run "glasspane.fab.cookies" (list :token token)) 'accepted))
      (should (string-search "* Top [1/2]" (glasspane-fab-test--text file)))
      (should (eq (funcall run "glasspane.fab.archive-tag" (list :token token)) 'stale))
      (setq token (funcall fresh))
      (should (eq (funcall run "glasspane.fab.archive-tag" (list :token token)) 'accepted))
      (should (string-match-p "^\\* Top \\[1/2\\] +:ARCHIVE:" (glasspane-fab-test--text file)))
      (setq token (funcall fresh))
      (should (eq (funcall run "glasspane.fab.move" (list :token token :how "down"))
                  'accepted))
      (should (string-prefix-p "* Second" (glasspane-fab-test--text file)))
      (should (eq (funcall run "glasspane.fab.move" (list :token token :how "sideways"))
                  'rejected))
      (should (eq (funcall run "glasspane.fab.cookies" '(:token "expired")) 'stale)))))

(ert-deftest glasspane-fab-test-clock-cancel-saves-the-file ()
  "Cancel clock removes the CLOCK line on disk, not only in the buffer."
  (glasspane-fab-test--with-file
      "* TODO Task\n"
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-min))
      (org-clock-in)
      (save-buffer))
    (unwind-protect
        (progn
          (should (string-search "CLOCK: [" (with-temp-buffer
                                              (insert-file-contents file)
                                              (buffer-string))))
          (should (eq (funcall (gethash "glasspane.fab.clock-cancel"
                                        jetpacs-action-handlers)
                               nil nil)
                      'accepted))
          (should-not (org-clocking-p))
          (should-not (buffer-modified-p (find-buffer-visiting file)))
          (should-not (string-search "CLOCK:" (with-temp-buffer
                                                (insert-file-contents file)
                                                (buffer-string)))))
      (when (org-clocking-p) (org-clock-cancel)))))

(ert-deftest glasspane-fab-test-clock-row-ticks-from-the-start ()
  "The detail band's Clock row: a Companion-ticked timer and the start time."
  (let* ((start (encode-time (list 0 30 16 28 10 2026)))
         (ms (truncate (* 1000 (float-time start)))))
    (glasspane-fab-test--advertised t
      (let ((json (jetpacs-node->canonical-json
                   (glasspane-detail--clock-value start "2026-10-28"))))
        (should (string-search "\"t\":\"material3.chronometer\"" json))
        (should (string-search (format "\"base_ms\":%d" ms) json))
        (should (string-search "Started 16:30" json)))
      (should (string-search "Started Tue 16:30"
                             (jetpacs-node->canonical-json
                              (glasspane-detail--clock-value
                               (encode-time (list 0 30 16 27 10 2026))
                               "2026-10-28")))))
    (glasspane-fab-test--advertised '()
      (let ((json (jetpacs-node->canonical-json
                   (glasspane-detail--clock-value start "2026-10-28"))))
        (should-not (string-search "chronometer" json))
        (should (string-search "Running since 16:30" json))))))

(ert-deftest glasspane-fab-test-dialog-actions-submit-and-write ()
  "Add child, set Effort, sort and clone go through their dialogs."
  (glasspane-fab-test--with-file
      "* Parent\n** b\n** a\n"
    (let (submit)
      (cl-letf (((symbol-function 'jetpacs-client) (lambda () 'fake))
                ((symbol-function 'jetpacs-flow-continue) (lambda (fn) (funcall fn)))
                ((symbol-function 'jetpacs-dialog-slot-show)
                 (lambda (_id spec &rest keys)
                   (jetpacs-check-profile spec 'dialog)
                   (setq submit (plist-get keys :on-submit)))))
        (let ((run (lambda (verb args)
                     (funcall (gethash verb jetpacs-action-handlers) args nil))))
          (should (eq (funcall run "glasspane.fab.add"
                               (list :token token :relation "child" :todo t))
                      'accepted))
          (funcall submit '(:gp-fab-title "Call plumber"))
          (should (string-search "** TODO Call plumber" (glasspane-fab-test--text file)))
          (should (eq (funcall run "glasspane.fab.effort" (list :token token)) 'accepted))
          (funcall submit '(:gp-fab-effort "1:30"))
          (should (string-search ":Effort:   1:30" (glasspane-fab-test--text file)))
          (should (eq (funcall run "glasspane.fab.sort" (list :token token)) 'accepted))
          (funcall submit '(:gp-fab-sort-method "a" :gp-fab-sort-reverse :json-false))
          (should (string-match-p "\\*\\* a\n\\*\\* b" (glasspane-fab-test--text file)))
          (should (eq (funcall run "glasspane.fab.clone" (list :token token)) 'accepted))
          (funcall submit '(:gp-fab-clone-n "2" :gp-fab-clone-shift "+1w"))
          (with-current-buffer (find-file-noselect file)
            (should (= 3 (how-many "^\\* Parent" (point-min) (point-max))))))))))

(ert-deftest glasspane-fab-test-quick-task-files-into-the-inbox ()
  "A quick task lands in the inbox, scheduled and tagged as asked."
  (glasspane-fab-test--with-file "* Seed\n"
    (let ((glasspane-fab-inbox "inbox.org")
          submit)
      (cl-letf (((symbol-function 'jetpacs-client) (lambda () 'fake))
                ((symbol-function 'jetpacs-flow-continue) (lambda (fn) (funcall fn)))
                ((symbol-function 'jetpacs-dialog-slot-show)
                 (lambda (_id spec &rest keys)
                   (jetpacs-check-profile spec 'dialog)
                   (setq submit (plist-get keys :on-submit)))))
        (should (eq (glasspane-fab--on-quick-task '(:date "2026-10-29" :area "Home") nil)
                    'accepted))
        (funcall submit '(:gp-fab-title "Buy filters" :gp-fab-when "2026-10-29"))
        (let ((text (glasspane-fab-test--text (expand-file-name "inbox.org" org-directory))))
          (should (string-search "* TODO Buy filters :Home:" text))
          (should (string-search "SCHEDULED: <2026-10-29 Thu>" text)))
        (should (eq (glasspane-fab--on-quick-task '(:date "junk") nil) 'rejected))
        (should (eq (glasspane-fab--on-quick-task '(:area "two words") nil) 'rejected))))))

(ert-deftest glasspane-fab-test-countdown-rides-a-reminder ()
  "Effort starts a countdown whose reminder fires at its end; stop clears it."
  (glasspane-fab-test--with-file "* Focus\n:PROPERTIES:\n:Effort:   0:25\n:END:\n"
    (let ((glasspane-fab--countdown nil) synced)
      (cl-letf (((symbol-function 'jetpacs-reminders-schedule-sync)
                 (lambda (owner) (push owner synced))))
        (should (eq (glasspane-fab--on-countdown (list :token token) nil) 'accepted))
        (should (glasspane-fab-countdown-active-p))
        (let ((r (car (glasspane-fab--reminders))))
          (should (equal (plist-get r :id) "glasspane-countdown"))
          (should (equal (plist-get r :body) "Focus"))
          (should (< (abs (- (plist-get r :at_ms)
                             (+ (* 1000 (float-time)) (* 25 60 1000))))
                     5000)))
        (should (equal synced '("glasspane")))
        (should (eq (glasspane-fab--on-countdown-stop nil nil) 'accepted))
        (should-not (glasspane-fab--reminders))))))

(ert-deftest glasspane-fab-test-outline-fab-only-for-the-read-document ()
  "Files' document host takes Glasspane's FAB only for the file it shows."
  (cl-letf (((symbol-function 'org-clocking-p) (lambda () nil)))
    (glasspane-fab-test--advertised t
      (cl-letf (((symbol-function 'jetpacs-reader-current-path-p)
                 (lambda (p) (equal p "/v/a.org"))))
        (let ((fab (glasspane-fab--outline-fab "/v/a.org")))
          (should (equal (glasspane-fab-test--labels fab)
                         '("New TODO" "New heading" "Run all code blocks" "Tangle"
                           "Update clock tables" "Time totals")))
          (should (plist-get (glasspane-fab-test--action fab "Tangle") :confirm)))
        (should-not (glasspane-fab--outline-fab "/v/other.org"))
        (should-not (glasspane-fab--outline-fab "/v/notes.txt"))
        (should (memq #'glasspane-fab--outline-fab jetpacs-files-editor-fab-functions))))))

(ert-deftest glasspane-fab-test-file-times-sums-the-clock ()
  "Time totals list each clocked top-level heading, longest first."
  (glasspane-fab-test--with-file
      (concat "* A\n:LOGBOOK:\nCLOCK: [2026-10-01 Thu 09:00]--[2026-10-01 Thu 09:30] =>  0:30\n:END:\n"
              "* B\n:LOGBOOK:\nCLOCK: [2026-10-01 Thu 10:00]--[2026-10-01 Thu 12:00] =>  2:00\n:END:\n"
              "* C\n")
    (should (equal (glasspane-fab-file-times file) '(("B" . 120) ("A" . 30))))))

(ert-deftest glasspane-fab-test-lifecycle-is-symmetric ()
  "Every FAB verb and the outline hook leave with the app and come back."
  (unwind-protect
      (progn
        (glasspane-fab-unregister)
        (dolist (v glasspane-fab--verbs)
          (should-not (gethash v jetpacs-action-handlers)))
        (should-not (memq #'glasspane-fab--outline-fab jetpacs-files-editor-fab-functions)))
    (glasspane-fab-register))
  (dolist (v glasspane-fab--verbs)
    (should (equal (jetpacs--owner-of "action" v) "glasspane"))))

(provide 'glasspane-fab-test)
;;; glasspane-fab-test.el ends here
