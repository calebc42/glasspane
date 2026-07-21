;;; glasspane-jetpacs-test.el --- Tests for glasspane-jetpacs
;;; Code:

(require 'glasspane-test-helpers)

;; ─── Capture ────────────────────────────────────────────────────────────────

(ert-deftest jetpacs-capture-fills-template ()
  "The filled capture template must be the one that actually runs."
  (let* ((file (make-temp-file "jetpacs-capture-test" nil ".org"))
         (org-capture-templates
          `(("t" "Task" entry (file ,file)
             "* TODO %^{Headline}\n%^{Notes|no notes}\n%?"))))
    (unwind-protect
        (progn
          (glasspane-org--do-capture "t" '(("Headline" . "Buy milk")
                                      ("Notes" . "2% fat")))
          (let ((content (with-current-buffer (find-file-noselect file)
                           (buffer-string))))
            (should (string-search "* TODO Buy milk" content))
            (should (string-search "2% fat" content))
            (should-not (string-search "%^{" content))))
      (delete-file file))))

(ert-deftest jetpacs-capture-shared-body ()
  "Text shared from another app is appended below the filled template."
  (let* ((file (make-temp-file "jetpacs-share-test" nil ".org"))
         (org-capture-templates
          `(("t" "Task" entry (file ,file) "* TODO %^{Headline}\n%?"))))
    (unwind-protect
        (progn
          (glasspane-org--do-capture "t" '(("Headline" . "Read article"))
                                "https://example.com/post\nInteresting bit.")
          (let ((content (with-current-buffer (find-file-noselect file)
                           (buffer-string))))
            (should (string-search "* TODO Read article" content))
            (should (string-search "https://example.com/post" content))
            (should (string-search "Interesting bit." content))))
      (delete-file file))))

(ert-deftest jetpacs-capture-submit-reads-form-and-rotates ()
  "org.capture.submit reads its fields through the capture `jetpacs-form'
and resets it — rotating the ids so stale device-side field state
can't resurface in the next capture."
  (let ((jetpacs--forms (make-hash-table :test 'equal))
        (jetpacs--ui-state (make-hash-table :test 'equal))
        (glasspane-ui--shared-text nil)
        (glasspane-ui--shared-subject nil)
        (recorded nil))
    (cl-letf (((symbol-function 'glasspane-org--capture-templates)
               (lambda () '(((key . "t") (description . "Task")
                             (prompts . ["Headline" "Notes"])))))
              ((symbol-function 'glasspane-org--do-capture)
               (lambda (key values &optional _body)
                 (setq recorded (cons key values))))
              ((symbol-function 'jetpacs-shell-push)
               (cl-function (lambda (&optional _tab &key _switch-to)))))
      ;; Values arrive as state.changed events keyed by the gen-0 ids.
      (jetpacs-ui-state-put "cap-Headline-0" "Buy milk")
      (jetpacs-ui-state-put "cap-Notes-0" "2% fat")
      (jetpacs--on-action '((action . "org.capture.submit")
                         (args . ((key . "t")))) nil)
      (should (equal recorded '("t" ("Headline" . "Buy milk")
                                ("Notes" . "2% fat"))))
      ;; The submit reset the form: ids rotated, values gone.
      (should (= 1 (jetpacs-form-gen (glasspane-capture--form))))
      (should-not (jetpacs-ui-state "cap-Headline-0")))))

;; ─── Reminders ──────────────────────────────────────────────────────────────

(ert-deftest jetpacs-upcoming-reminders ()
  "Timed items within the horizon become reminder specs; untimed don't."
  (let* ((file (make-temp-file "jetpacs-remind" nil ".org"))
         (tomorrow (glasspane-ui--shift-date (format-time-string "%Y-%m-%d")
                                            1 'day)))
    (with-temp-file file
      (insert (format "* TODO Standup\nSCHEDULED: <%s 09:15>\n" tomorrow)
              (format "* TODO Untimed thing\nSCHEDULED: <%s>\n" tomorrow)))
    (unwind-protect
        (let ((org-agenda-files (list file)))
          (jetpacs-org-cache-invalidate 'glasspane)
          (let ((rems (glasspane-org--upcoming-reminders 48)))
            (should (= (length rems) 1))
            (let ((r (car rems)))
              (should (equal (alist-get 'title r) "Standup"))
              (should (> (alist-get 'at_ms r)
                         (truncate (* 1000 (float-time)))))
              (should (string-prefix-p "09:15" (alist-get 'body r))))))
      (delete-file file))))

;; ─── Widget items ───────────────────────────────────────────────────────────

(ert-deftest jetpacs-widget-items ()
  "Widget items compose meta, flag overdue, omit nil fields, cap at 20."
  (let ((today (org-today)))
    (cl-letf (((symbol-function 'glasspane-org--agenda-items)
               (lambda (&rest _)
                 (append
                  (list `((headline . "Standup") (time . "09:15") (todo . "TODO")
                          (type . "scheduled") (extra . "Scheduled: ")
                          (ts-date . ,today) (file . "/tmp/a.org")
                          (ref . ((file . "/tmp/a.org") (pos . 1)
                                  (headline . "Standup"))))
                        `((headline . "Report") (todo . "TODO")
                          (type . "past-scheduled") (extra . "Sched. 3x: ")
                          (ts-date . ,(- today 3)) (file . "/tmp/b.org"))
                        '((headline . "Shipped") (todo . "DONE"))
                        '((headline . "No time")))
                  (make-list 25 '((headline . "Filler") (time . "10:00")))))))
      (let ((items (glasspane-ui--widget-items)))
        ;; 20 capped rows plus the two injected dividers.
        (should (= (length items) 22))
        (should (equal (alist-get 'divider (nth 0 items)) "Overdue"))
        (let ((od (nth 1 items)))
          (should (equal (alist-get 'text od) "Report"))
          (should (equal (alist-get 'meta od) "Sched. 3x · b.org"))
          (should (equal (alist-get 'icon od) "scheduled"))
          (should (equal (alist-get 'button od) "todo_open"))
          (should (equal (alist-get 'action (alist-get 'on_button od))
                         "heading.todo-cycle")))
        (should (equal (alist-get 'divider (nth 2 items)) "Today"))
        (let ((first (nth 3 items)))
          (should (equal (alist-get 'text first) "Standup"))
          (should (equal (alist-get 'todo first) "TODO"))
          ;; A bare "Scheduled" qualifier is dropped: time + file only.
          (should (equal (alist-get 'meta first) "09:15 · a.org"))
          (should (equal (alist-get 'icon first) "scheduled"))
          (should (eq (alist-get 'tap_in_app first) t))
          (should (equal (alist-get 'action (alist-get 'on_tap first))
                         "heading.tap"))
          (should (equal (alist-get 'file (alist-get 'args (alist-get 'on_tap first)))
                         "/tmp/a.org"))
          (should-not (alist-get 'done first)))
        (let ((done (nth 4 items)))
          (should (eq (alist-get 'done done) t))
          (should (equal (alist-get 'button done) "todo_done"))
          ;; No time/extra/file → no meta at all.
          (should-not (assq 'meta done)))
        (let ((plain (nth 5 items)))
          (should (equal (alist-get 'text plain) "No time"))
          (should-not (assq 'todo plain))
          (should-not (assq 'button plain)))))))

;; ─── Files sandbox ──────────────────────────────────────────────────────────

;; ─── Keymap labels ──────────────────────────────────────────────────────────

;; ─── Agenda extraction ──────────────────────────────────────────────────────

(ert-deftest jetpacs-agenda-extraction ()
  "Items extract; the private buffer dies; the user's agenda survives."
  (let* ((file (make-temp-file "jetpacs-agenda-test" nil ".org")))
    (with-temp-file file
      (insert (format "* TODO Water plants\nSCHEDULED: <%s>\n"
                      (format-time-string "%Y-%m-%d %a"))))
    (unwind-protect
        (let ((org-agenda-files (list file)))
          (with-current-buffer (get-buffer-create "*Org Agenda*")
            (erase-buffer)
            (insert "user content"))
          (jetpacs-org-cache-invalidate 'glasspane)
          (should (cl-some (lambda (it)
                             (equal (alist-get 'headline it) "Water plants"))
                           (glasspane-org--agenda-items 'day nil)))
          (should-not (get-buffer "*Jetpacs Agenda*"))
          (should (equal (with-current-buffer "*Org Agenda*" (buffer-string))
                         "user content")))
      (delete-file file))))

(ert-deftest jetpacs-agenda-anchored-extraction ()
  "Navigation anchors actually change the extracted range."
  (let* ((file (make-temp-file "jetpacs-agenda-nav" nil ".org"))
         (tomorrow (glasspane-ui--shift-date
                    (format-time-string "%Y-%m-%d") 1 'day)))
    (with-temp-file file
      (insert (format "* TODO Future thing\nSCHEDULED: <%s>\n" tomorrow)))
    (unwind-protect
        (let ((org-agenda-files (list file)))
          (jetpacs-org-cache-invalidate 'glasspane)
          (should-not (cl-some (lambda (it)
                                 (equal (alist-get 'headline it) "Future thing"))
                               (glasspane-org--agenda-items 'day nil)))
          (should (cl-some (lambda (it)
                             (equal (alist-get 'headline it) "Future thing"))
                           (glasspane-org--agenda-items 'day tomorrow))))
      (delete-file file))))

;; ─── Search: query parsing, matching, builder ───────────────────────────────

(ert-deftest jetpacs-search-parse-normalizes-sexp-queries ()
  "Hand-typed elisp-isms — quoted or bare symbols — become org-ql strings."
  (should (equal (jetpacs-org-parse-query "(tags 'server)") '(tags "server")))
  (should (equal (jetpacs-org-parse-query "(tags \"server\")") '(tags "server")))
  (should (equal (jetpacs-org-parse-query "'(and (todo NEXT) (tags 'a b))")
                 '(and (todo "NEXT") (tags "a" "b"))))
  ;; Symbols org-ql assigns meaning survive: dates, comparators, keywords.
  (should (equal (jetpacs-org-parse-query "(deadline :on today)")
                 '(deadline :on today)))
  (should (equal (jetpacs-org-parse-query "(priority >= \"B\")")
                 '(priority >= "B"))))

(ert-deftest jetpacs-search-parse-tokens-and-text ()
  "Token queries AND together; quoted phrases stay whole; empty is nil."
  (should (equal (jetpacs-org-parse-query
                  "todo:TODO,NEXT tags:work \"buy milk\" cheese")
                 '(and (todo "TODO" "NEXT") (tags "work")
                       (regexp "buy milk") (regexp "cheese"))))
  (should (equal (jetpacs-org-parse-query "milk") '(regexp "milk")))
  (should (null (jetpacs-org-parse-query "   "))))

(ert-deftest jetpacs-search-parse-unbalanced-query-errors ()
  "A malformed sexp must error visibly, never silently match nothing."
  (should-error (jetpacs-org-parse-query "(tags \"server\"")
                :type 'user-error))

(ert-deftest jetpacs-search-matches-quoted-tag-query ()
  "(tags 'server) — the tag-chip query a user retypes — finds the entry."
  (jetpacs-tests--with-search-fixture
   (should (equal (jetpacs-tests--search-headlines "(tags 'server)")
                  '("Fix the server")))
   (should (equal (jetpacs-tests--search-headlines "(tags \"server\")")
                  '("Fix the server")))))

(ert-deftest jetpacs-search-tags-and-todo-case-sensitive ()
  "Tags and TODO keywords are case-sensitive org data."
  (jetpacs-tests--with-search-fixture
   (should (equal (jetpacs-tests--search-headlines "tags:Server")
                  '("Deploy the Server")))
   (should (equal (jetpacs-tests--search-headlines "tags:server")
                  '("Fix the server")))
   (should-not (jetpacs-tests--search-headlines "(todo \"todo\")"))))

(ert-deftest jetpacs-search-free-text-case-insensitive ()
  "Free text folds case and reaches the entry body."
  (jetpacs-tests--with-search-fixture
   (should (equal (jetpacs-tests--search-headlines "MILK") '("Buy milk")))
   (should (equal (jetpacs-tests--search-headlines "semi-skimmed")
                  '("Buy milk")))))

(ert-deftest jetpacs-search-query-predicates ()
  "The built-in interpreter covers the query-builder's vocabulary."
  (jetpacs-tests--with-search-fixture
   (should (equal (jetpacs-tests--search-headlines "(done)")
                  '("Deploy the Server")))
   (should (equal (jetpacs-tests--search-headlines "(todo)")
                  '("Fix the server" "Call plumber")))
   (should (equal (jetpacs-tests--search-headlines "(priority \"A\")")
                  '("Fix the server")))
   (should (equal (jetpacs-tests--search-headlines "(and (todo \"TODO\") (tags 'home))")
                  '("Call plumber")))
   (should (equal (jetpacs-tests--search-headlines "(or (tags 'urgent) (tags 'Server))")
                  '("Fix the server" "Deploy the Server")))
   (should (equal (jetpacs-tests--search-headlines "(deadline :on today)")
                  '("Fix the server")))
   (should-not (jetpacs-tests--search-headlines "(deadline :to -1)"))))

(ert-deftest jetpacs-search-unknown-term-errors ()
  "A term the engine can't run must error, not return nothing."
  (jetpacs-tests--with-search-fixture
   (should-error (glasspane-org--search "(frobnicate \"x\")")
                 :type 'user-error)))

(ert-deftest jetpacs-search-builder-generates-org-ql ()
  "The builder writes a real org-ql sexp that round-trips through the parser."
  (let ((jetpacs--ui-state (make-hash-table :test 'equal)))
    (should (equal (glasspane-ui--search-filter-query) ""))
    (jetpacs-ui-state-put "search-filter-todo" "TODO")
    (jetpacs-ui-state-put "search-filter-tags" ["server" "urgent"])
    (jetpacs-ui-state-put "search-filter-due" "Today")
    (jetpacs-ui-state-put "search-filter-text" "reboot")
    (should (equal (jetpacs-org-parse-query (glasspane-ui--search-filter-query))
                   '(and (todo "TODO") (tags "server") (tags "urgent")
                         (deadline :on today) (regexp "reboot")))))
  ;; A lone filter emits a bare clause — the same shape a tag tap makes.
  (let ((jetpacs--ui-state (make-hash-table :test 'equal)))
    (jetpacs-ui-state-put "search-filter-tags" ["home"])
    (should (equal (glasspane-ui--search-filter-query) "(tags \"home\")"))))

;; ─── Agenda date arithmetic & widgets ───────────────────────────────────────

(ert-deftest jetpacs-agenda-date-math ()
  (should (equal (glasspane-ui--shift-date "2026-07-01" 1 'day) "2026-07-02"))
  (should (equal (glasspane-ui--shift-date "2026-07-01" -1 'day) "2026-06-30"))
  (should (equal (glasspane-ui--shift-date "2026-07-01" -1 'week) "2026-06-24"))
  (should (equal (glasspane-ui--shift-date "2026-01-31" 1 'month) "2026-02-28"))
  (should (equal (glasspane-ui--shift-date "2024-01-31" 1 'month) "2024-02-29"))
  (should (equal (glasspane-ui--shift-date "2026-12-15" 1 'month) "2027-01-15"))
  (should (equal (glasspane-ui--shift-date "2026-01-15" -1 'month) "2025-12-15")))

(ert-deftest jetpacs-agenda-widgets-serialize ()
  "Agenda cards, nav rows, and the month grid build and serialize."
  (let ((item `((headline . "Ship release")
                (todo . "TODO")
                (time . "10:00")
                (type . "scheduled")
                (file . "/tmp/x.org")
                (priority . "A")
                (tags . ["work" "urgent"])
                (ref . ((file . "/tmp/x.org") (pos . 1)
                        (headline . "Ship release"))))))
    (dolist (node (list (glasspane-ui--agenda-card item)
                        (glasspane-ui--agenda-card
                         '((headline . "Done thing") (todo . "DONE")))
                        (glasspane-ui--agenda-nav-row "day" "2026-07-01")
                        (glasspane-ui--agenda-nav-row "week" "2026-07-01")
                        (glasspane-ui--agenda-nav-row "month" "2026-07-01")
                        (glasspane-ui--agenda-month-view nil "2026-02-14")))
      (should (consp node))
      (should (stringp (json-serialize node :null-object :null
                                       :false-object :false))))))

;; ─── Prompt dialogs ─────────────────────────────────────────────────────────

;; ─── Tier 1 keymap menus ────────────────────────────────────────────────────

(ert-deftest glasspane-magit-tier1 ()
  "The curated magit pie registers, fits the pie, and serializes."
  (with-temp-buffer
    (setq major-mode 'magit-status-mode)
    (let ((builder (jetpacs-keymap--tier1-builder (current-buffer))))
      (should (functionp builder))
      (let* ((spec (funcall builder (current-buffer)))
             (cats (append (alist-get 'categories spec) nil)))
        (should (equal (alist-get 'center_label spec) "Magit"))
        (should (= (length cats) 4))
        (dolist (cat cats)
          (should (<= (length (append (alist-get 'bindings cat) nil)) 8)))
        (let ((share (cl-find "Share" cats
                              :key (lambda (c) (alist-get 'label c))
                              :test #'equal)))
          (should (cl-every (lambda (b) (alist-get 'is_prefix b))
                            (append (alist-get 'bindings share) nil))))
        (should (stringp (json-serialize spec :null-object :null
                                         :false-object :false))))))
  (with-temp-buffer
    (should-not (jetpacs-keymap--tier1-builder (current-buffer)))))

;; ─── Messages view ──────────────────────────────────────────────────────────

;; ─── Detail-view properties editor ──────────────────────────────────────────

(ert-deftest jetpacs-detail-properties ()
  "Property rows: colon-free editable keys, read-only ID, empty-value adds.
Also pins the org behavior the + Add flow depends on: a property set to
the empty string must still be returned by `org-entry-properties'."
  ;; Row shapes.
  (let* ((ref '((file . "/tmp/x.org") (pos . 1) (headline . "T")))
         (row (glasspane-ui--property-row "EFFORT" "2h" ref 1))
         (id-row (glasspane-ui--property-row "ID" "abc-123" ref 1)))
    (should (equal (alist-get 't row) "row"))
    ;; Key column: plain label, no colons.
    (let* ((key-box (aref (alist-get 'children row) 0))
           (key-text (aref (alist-get 'children key-box) 0)))
      (should (equal (alist-get 'text key-text) "EFFORT")))
    ;; Value column: an input for normal keys, read-only text for ID.
    (let* ((val-box (aref (alist-get 'children row) 1))
           (input (aref (alist-get 'children val-box) 0)))
      (should (equal (alist-get 't input) "text_input"))
      (should (equal (alist-get 'value input) "2h")))
    (let* ((val-box (aref (alist-get 'children id-row) 1))
           (node (aref (alist-get 'children val-box) 0)))
      (should (equal (alist-get 't node) "text"))))
  ;; Empty-valued properties survive extraction (the + Add contract).
  (let ((file (make-temp-file "jetpacs-props" nil ".org")))
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (insert "* Task\n")
          (goto-char (point-min))
          (org-mode)
          (org-set-property "NEWKEY" "")
          (should (assoc "NEWKEY" (org-entry-properties nil 'standard))))
      (delete-file file))))

(ert-deftest glasspane-ghostel-render-dead-and-live ()
  "The skin dispatches for ghostel-mode; input surfaces only when live."
  (jetpacs-tests--with-fake-ghostel "*ghostel-render-test*"
    ;; Live: transcript + key chips + input row, all lint-clean.
    (let* ((nodes (jetpacs-render-buffer (current-buffer)))
           (json (json-serialize (apply #'jetpacs-column nodes)
                                 :null-object :null :false-object :false)))
      (should-not (jetpacs-lint-spec (apply #'jetpacs-column nodes)))
      (should (string-search "file-a" json))
      (should (string-search "ghostel/*ghostel-render-test*/0" json))
      (should (string-search "ghostel.send" json))
      (should (string-search "ghostel.send-key" json))
      (should (string-search "Esc" json))
      ;; Terminal input must never queue for replay.
      (should-not (string-search "\"when_offline\":\"queue\"" json)))
    ;; Dead: the transcript stays, the input surface goes away.
    (delete-process ghostel--process)
    (let* ((nodes (jetpacs-render-buffer (current-buffer)))
           (json (json-serialize (apply #'jetpacs-column nodes)
                                 :null-object :null :false-object :false)))
      (should-not (jetpacs-lint-spec (apply #'jetpacs-column nodes)))
      (should (string-search "no live process" json))
      (should (string-search "file-a" json))
      (should-not (string-search "ghostel.send" json)))))

(ert-deftest glasspane-ghostel-send-encodes-and-bumps-gen ()
  "ghostel.send writes UTF-8 bytes then Return; a send rotates the field id."
  (let (sent keys)
    (cl-letf (((symbol-function 'ghostel-send-string)
               (lambda (s) (push s sent)))
              ((symbol-function 'ghostel-send-key)
               (lambda (k &optional m) (push (cons k m) keys))))
      (jetpacs-tests--with-fake-ghostel "*ghostel-send-test*"
        (funcall (gethash "ghostel.send" jetpacs-action-handlers)
                 '((buffer . "*ghostel-send-test*") (value . "echo héllo")) nil)
        (should (equal sent (list (encode-coding-string "echo héllo" 'utf-8))))
        (should (equal keys '(("return" . nil))))
        ;; The bumped generation hands the client a fresh input field.
        (let ((json (json-serialize
                     (apply #'jetpacs-column
                            (jetpacs-render-buffer (current-buffer)))
                     :null-object :null :false-object :false)))
          (should (string-search "ghostel/*ghostel-send-test*/1" json)))
        ;; An empty submit is a bare Enter, no payload write.
        (funcall (gethash "ghostel.send" jetpacs-action-handlers)
                 '((buffer . "*ghostel-send-test*") (value . "")) nil)
        (should (= 1 (length sent)))
        (should (= 2 (length keys)))))
    ;; Boundary: a non-ghostel buffer never reaches the senders.
    (setq sent nil keys nil)
    (cl-letf (((symbol-function 'ghostel-send-string)
               (lambda (s) (push s sent)))
              ((symbol-function 'ghostel-send-key)
               (lambda (k &optional m) (push (cons k m) keys))))
      (funcall (gethash "ghostel.send" jetpacs-action-handlers)
               `((buffer . ,(buffer-name (get-buffer-create "*scratch*")))
                 (value . "rm -rf /")) nil)
      (should-not sent)
      (should-not keys))))

(ert-deftest glasspane-ghostel-send-key-allowlist ()
  "ghostel.send-key presses exactly the curated keys, nothing else."
  (let (keys)
    (cl-letf (((symbol-function 'ghostel-send-key)
               (lambda (k &optional m) (push (cons k m) keys))))
      (jetpacs-tests--with-fake-ghostel "*ghostel-keys-test*"
        (funcall (gethash "ghostel.send-key" jetpacs-action-handlers)
                 '((buffer . "*ghostel-keys-test*") (key . "up") (mods . "")) nil)
        (funcall (gethash "ghostel.send-key" jetpacs-action-handlers)
                 '((buffer . "*ghostel-keys-test*") (key . "c") (mods . "ctrl")) nil)
        (should (equal (reverse keys) '(("up" . nil) ("c" . "ctrl"))))
        ;; Off-list key, and an on-list key with the wrong modifiers.
        (funcall (gethash "ghostel.send-key" jetpacs-action-handlers)
                 '((buffer . "*ghostel-keys-test*") (key . "x") (mods . "")) nil)
        (funcall (gethash "ghostel.send-key" jetpacs-action-handlers)
                 '((buffer . "*ghostel-keys-test*") (key . "c") (mods . "")) nil)
        (should (= 2 (length keys)))))))

(provide 'glasspane-jetpacs-test)
