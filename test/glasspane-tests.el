;;; glasspane-tests.el --- ERT suite for the Glasspane app -*- lexical-binding: t; -*-

;; Run from the repo root (any Emacs 28+), with the jetpacs submodule checked out:
;;   git submodule update --init
;;   emacs -Q --batch -l test/glasspane-tests.el -f ert-run-tests-batch-and-exit
;;
;; The Jetpacs core this app builds on comes from the `jetpacs' git submodule
;; (emacs/core there); this repo carries only the Glasspane Tier-1 sources.

;;; Code:

(defvar jetpacs-tests--dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing this test file.")

;; Core from the jetpacs submodule; the app sources from this repo.
(dolist (dir '("../jetpacs/emacs/core" "../emacs/apps" "../emacs/apps/glasspane"))
  (add-to-list 'load-path (expand-file-name dir jetpacs-tests--dir)))

(require 'ert)
(require 'cl-lib)
(require 'jetpacs)
(require 'jetpacs-triggers)
(require 'jetpacs-device)
(require 'jetpacs-apps)
(require 'jetpacs-automations)
(require 'jetpacs-widgets)
(require 'jetpacs-lint)
(require 'jetpacs-shell)
(require 'glasspane-org)
(require 'jetpacs-keymap)
(require 'jetpacs-magit)
(require 'jetpacs-files)
(require 'jetpacs-minibuffer)
(require 'glasspane-ui)
(require 'jetpacs-emacs-ui)
(require 'jetpacs-complete)
(require 'jetpacs-sync)
(require 'glasspane-demo)
(require 'glasspane-gallery)
(require 'glasspane-config)
(require 'glasspane-journal)
(require 'glasspane-views)
(require 'glasspane-automations)
(require 'glasspane-notes)
(require 'glasspane-srs)

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
          (glasspane-org-cache-invalidate)
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

;; ─── Extraction cache ───────────────────────────────────────────────────────

(ert-deftest glasspane-org-cache-memoises ()
  "Readers memoise until `glasspane-org-cache-invalidate' drops the table."
  (let ((n 0))
    (cl-letf (((symbol-function 'glasspane-org--todo-items-1)
               (lambda (_files) (setq n (1+ n)) '(fake))))
      (glasspane-org-cache-invalidate)
      (glasspane-org--todo-items)
      (glasspane-org--todo-items)
      (should (= n 1))
      (glasspane-org-cache-invalidate)
      (glasspane-org--todo-items)
      (should (= n 2)))))

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
          (glasspane-org-cache-invalidate)
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
          (glasspane-org-cache-invalidate)
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
  (should (equal (glasspane-org--parse-query "(tags 'server)") '(tags "server")))
  (should (equal (glasspane-org--parse-query "(tags \"server\")") '(tags "server")))
  (should (equal (glasspane-org--parse-query "'(and (todo NEXT) (tags 'a b))")
                 '(and (todo "NEXT") (tags "a" "b"))))
  ;; Symbols org-ql assigns meaning survive: dates, comparators, keywords.
  (should (equal (glasspane-org--parse-query "(deadline :on today)")
                 '(deadline :on today)))
  (should (equal (glasspane-org--parse-query "(priority >= \"B\")")
                 '(priority >= "B"))))

(ert-deftest jetpacs-search-parse-tokens-and-text ()
  "Token queries AND together; quoted phrases stay whole; empty is nil."
  (should (equal (glasspane-org--parse-query
                  "todo:TODO,NEXT tags:work \"buy milk\" cheese")
                 '(and (todo "TODO" "NEXT") (tags "work")
                       (regexp "buy milk") (regexp "cheese"))))
  (should (equal (glasspane-org--parse-query "milk") '(regexp "milk")))
  (should (null (glasspane-org--parse-query "   "))))

(ert-deftest jetpacs-search-parse-unbalanced-query-errors ()
  "A malformed sexp must error visibly, never silently match nothing."
  (should-error (glasspane-org--parse-query "(tags \"server\"")
                :type 'user-error))

(defmacro jetpacs-tests--with-search-fixture (&rest body)
  "Run BODY with a temp org agenda file of known headings."
  `(let ((file (make-temp-file "jetpacs-search" nil ".org")))
     (with-temp-file file
       (insert "* TODO [#A] Fix the server :server:urgent:\n"
               "DEADLINE: <" (format-time-string "%Y-%m-%d") ">\n"
               "* DONE Deploy the Server :Server:\n"
               "* Buy milk :home:\n"
               "Semi-skimmed preferred.\n"
               "* TODO Call plumber :home:\n"))
     (unwind-protect
         (let ((org-agenda-files (list file)))
           (glasspane-org-cache-invalidate)
           ,@body)
       (delete-file file))))

(defun jetpacs-tests--search-headlines (query)
  "Headlines returned for QUERY, in file order."
  (mapcar (lambda (it) (alist-get 'headline it))
          (glasspane-org--search query)))

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
    (should (equal (glasspane-org--parse-query (glasspane-ui--search-filter-query))
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

(ert-deftest jetpacs-magit-tier1 ()
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

;; ─── Buffer-view line numbers ───────────────────────────────────────────────

(require 'jetpacs-buffer)

(defun jetpacs-tests--first-span-text (node)
  (alist-get 'text (aref (alist-get 'spans node) 0)))

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

;; ─── Shell ──────────────────────────────────────────────────────────────────

;; ─── Transport ──────────────────────────────────────────────────────────────

;; ─── Toast forwarding ───────────────────────────────────────────────────────

;; ─── Completion bridge ──────────────────────────────────────────────────────

;; ─── Editor sync (v2) ───────────────────────────────────────────────────────

;; ─── Pairing auth ───────────────────────────────────────────────────────────

;; ─── Demo files ─────────────────────────────────────────────────────────────

(ert-deftest glasspane-demo-setup-writes-files ()
  "Setup writes every tour file, non-trivially sized, and is idempotent."
  (let ((dir (make-temp-file "glasspane-demo" t)))
    (unwind-protect
        (progn
          (glasspane-demo-setup dir)
          (glasspane-demo-setup dir)          ; overwrite must not error
          (dolist (f '("demo.el" "demo.py" "demo.sh" "demo.c" "demo.org"))
            (let ((path (expand-file-name f dir)))
              (should (file-exists-p path))
              (should (> (file-attribute-size (file-attributes path)) 200)))))
      (delete-directory dir t))))

(ert-deftest glasspane-demo-el-is-tour-ready ()
  "The elisp tour file exercises the bridge features it claims to.
Its wrong-arity call must reference a function defined in the same
file (so the byte-compiler can flag it), and completion must fire on
the text it tells the user to type."
  (let ((content (cdr (assoc "demo.el" glasspane-demo--files))))
    (should (string-search "(demo-greet \"world\" 'oops)" content))
    (should (string-search "(defun demo-greet (name)" content))
    ;; The completion instruction actually completes.
    (let ((result (jetpacs-complete-in-text "demo.el" "(buffer-sub" 11)))
      (should result)
      (should (equal (car result) "buffer-sub")))))

;; ─── Org tables: emitter and actions ────────────────────────────────────────

(ert-deftest glasspane-org-rich-table-node ()
  "Org tables emit native table nodes: header, rule, aligns, cell taps."
  (let* ((body (concat "| Item | Qty |\n"
                       "|------+-----|\n"
                       "| a    |   1 |\n"
                       "| bb   |   2 |\n"))
         (table (car (glasspane-org-rich-body body nil "/tmp/t.org" 10))))
    (should (equal (alist-get 't table) "table"))
    (let* ((rows (append (alist-get 'rows table) nil))
           (r0 (nth 0 rows)) (r1 (nth 1 rows)) (r2 (nth 2 rows)))
      (should (= (length rows) 4))
      (should (eq (alist-get 'header r0) t))
      (should (eq (alist-get 'rule r1) t))
      ;; The numeric column right-aligns (org's own heuristic).
      (should (equal (append (alist-get 'aligns table) nil) '("start" "end")))
      ;; Cells carry edit actions with real-file positions baked in,
      ;; and a long-press menu for row/column operations.
      (let* ((cell (aref (alist-get 'cells r2) 0))
             (tap (alist-get 'on_tap cell))
             (long (alist-get 'on_long_tap cell)))
        (should (equal (alist-get 'action tap) "org.table.edit"))
        (should (equal (alist-get 'file (alist-get 'args tap)) "/tmp/t.org"))
        (should (integerp (alist-get 'pos (alist-get 'args tap))))
        (should (equal (alist-get 'action long) "org.table.cell-menu"))
        (should (equal (alist-get 'args long) (alist-get 'args tap)))))
    ;; Add affordances point back at the table.
    (should (equal (alist-get 'action (alist-get 'on_add_row table))
                   "org.table.add-row"))
    (should (equal (alist-get 'action (alist-get 'on_add_col table))
                   "org.table.add-col"))))

(ert-deftest glasspane-org-rich-table-readonly-without-context ()
  "Without file context the table renders, but nothing is tappable."
  (let ((table (car (glasspane-org-rich-body "| a | b |\n" nil))))
    (should (equal (alist-get 't table) "table"))
    (should-not (alist-get 'on_add_row table))
    (should-not (alist-get 'on_add_col table))
    (let ((cell (aref (alist-get 'cells (aref (alist-get 'rows table) 0)) 0)))
      (should-not (alist-get 'on_tap cell)))
    ;; A lone row group is not a header.
    (should-not (alist-get 'header (aref (alist-get 'rows table) 0)))))

(ert-deftest glasspane-org-rich-table-cookie-alignment ()
  "Cookie rows configure column alignment and drop out of display."
  (let ((table (car (glasspane-org-rich-body "| <c> | <r> |\n| a | b |\n" nil))))
    (should (equal (append (alist-get 'aligns table) nil) '("center" "end")))
    (should (= (length (alist-get 'rows table)) 1))))

(ert-deftest glasspane-org-rich-emphasis-preserves-trailing-space ()
  "Whitespace after inline objects survives rendering.
Org stores it as `:post-blank' on the object — it is in neither the
object's contents nor the next string, so the emitter must re-add it."
  (let* ((node (car (glasspane-org-rich-body
                     "a /it/ b *bo*  c ~vb~ d [[https://e.org][ln]] e"
                     nil)))
         (text (mapconcat (lambda (sp) (alist-get 'text sp))
                          (alist-get 'spans node) "")))
    (should (equal text "a it b bo  c vb d ln e"))))

;; ─── Org babel results: foldable and read-only ──────────────────────────────

(ert-deftest glasspane-org-rich-results-foldable-and-inert ()
  "Babel #+RESULTS render inside a foldable section without edit taps."
  ;; Table results: no cell taps, no menus, no add affordances.
  (let* ((node (car (glasspane-org-rich-body
                     "#+RESULTS:\n| a | b |\n| 1 | 2 |\n"
                     nil "/tmp/t.org" 10))))
    (should (equal (alist-get 't node) "collapsible"))
    (should (equal (alist-get 'text (alist-get 'header node)) "RESULTS"))
    (should-not (alist-get 'collapsed node))    ; visible until folded
    (let ((table (aref (alist-get 'children node) 0)))
      (should (equal (alist-get 't table) "table"))
      (should-not (alist-get 'on_add_row table))
      (should-not (alist-get 'on_add_col table))
      (let ((cell (aref (alist-get 'cells (aref (alist-get 'rows table) 0)) 0)))
        (should-not (alist-get 'on_tap cell))
        (should-not (alist-get 'on_long_tap cell)))))
  ;; Fixed-width results (the ": value" form) fold too.
  (let ((node (car (glasspane-org-rich-body "#+RESULTS:\n: 3\n"
                                            nil "/tmp/t.org" 10))))
    (should (equal (alist-get 't node) "collapsible"))
    (should (equal (alist-get 'text (alist-get 'header node)) "RESULTS")))
  ;; The same table without #+RESULTS stays editable.
  (let ((table (car (glasspane-org-rich-body "| a | b |\n" nil "/tmp/t.org" 10))))
    (should (equal (alist-get 't table) "table"))
    (should (alist-get 'on_add_row table))))

(ert-deftest glasspane-ui-table-edit-recalculates ()
  "The org.table.edit handler writes the field and recalculates #+TBLFM."
  (let ((file (make-temp-file "jetpacs-table-test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "| Item   | Qty | Cost |\n"
                    "|--------+-----+------|\n"
                    "| apples |   2 |    4 |\n"
                    "#+TBLFM: $3=$2*2\n"))
          (let (pos)
            (with-temp-buffer
              (insert-file-contents file)
              (goto-char (point-min))
              (search-forward "| apples |")
              (setq pos (point)))     ; inside the Qty field
            (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "5"))
                      ((symbol-function 'jetpacs-shell-push) (lambda (&rest _)))
                      ((symbol-function 'jetpacs-shell-notify)
                       (lambda (text) (ert-fail text))))
              (funcall (gethash "org.table.edit" jetpacs-action-handlers)
                       `((file . ,file) (pos . ,pos)) nil)))
          (let ((content (with-temp-buffer
                           (insert-file-contents file) (buffer-string))))
            ;; Qty written, Cost recalculated by the formula.
            (should (string-match-p "| apples | +5 | +10 |" content))))
      (delete-file file))))

(ert-deftest glasspane-ui-table-edit-formula-cell-edits-formula ()
  "Tapping a #+TBLFM-computed cell edits the formula, not the value
the next recalculation would overwrite."
  (let ((file (make-temp-file "jetpacs-table-test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "| Item   | Qty | Cost |\n"
                    "|--------+-----+------|\n"
                    "| apples |   2 |    4 |\n"
                    "#+TBLFM: $3=$2*2\n"))
          (let (pos prompt seed)
            (with-temp-buffer
              (insert-file-contents file)
              (goto-char (point-min))
              (search-forward "|    4")
              (setq pos (point)))       ; inside the computed Cost field
            (cl-letf (((symbol-function 'read-string)
                       (lambda (p &optional initial &rest _)
                         (setq prompt p seed initial) "$2*3"))
                      ((symbol-function 'jetpacs-shell-push) (lambda (&rest _)))
                      ((symbol-function 'jetpacs-shell-notify)
                       (lambda (text) (ert-fail text))))
              (funcall (gethash "org.table.edit" jetpacs-action-handlers)
                       `((file . ,file) (pos . ,pos)) nil))
            ;; The dialog names the formula target and seeds its body.
            (should (string-match-p "\\$3" prompt))
            (should (equal seed "$2*2"))
            (let ((content (with-temp-buffer
                             (insert-file-contents file) (buffer-string))))
              (should (string-match-p "#\\+TBLFM: \\$3=\\$2\\*3" content))
              (should (string-match-p "| apples | +2 | +6 |" content)))))
      (delete-file file))))

(ert-deftest glasspane-ui-table-cell-menu-deletes-row-and-column ()
  "The long-press menu deletes the row and column at the tapped cell."
  (let ((file (make-temp-file "jetpacs-table-test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "| a | b | c |\n| d | e | f |\n"))
          (let ((choice "Delete row"))
            (cl-letf (((symbol-function 'completing-read)
                       (lambda (&rest _) choice))
                      ((symbol-function 'jetpacs-shell-push) (lambda (&rest _)))
                      ((symbol-function 'jetpacs-shell-notify)
                       (lambda (text) (ert-fail text))))
              ;; Delete the first row, then the first remaining column.
              (funcall (gethash "org.table.cell-menu" jetpacs-action-handlers)
                       `((file . ,file) (pos . 3)) nil)
              (setq choice "Delete column")
              (funcall (gethash "org.table.cell-menu" jetpacs-action-handlers)
                       `((file . ,file) (pos . 3)) nil)))
          (let ((content (with-temp-buffer
                           (insert-file-contents file) (buffer-string))))
            (should (string-match-p "\\`| e | f |" content))
            (should-not (string-match-p "| a " content))))
      (delete-file file))))

(ert-deftest glasspane-ui-table-add-row-and-column ()
  "add-row appends an empty row; add-col appends an empty column at the right."
  (let ((file (make-temp-file "jetpacs-table-test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "| a | b |\n| c | d |\n"))
          (cl-letf (((symbol-function 'jetpacs-shell-push) (lambda (&rest _)))
                    ((symbol-function 'jetpacs-shell-notify)
                     (lambda (text) (ert-fail text))))
            (funcall (gethash "org.table.add-row" jetpacs-action-handlers)
                     `((file . ,file) (pos . 1)) nil)
            (funcall (gethash "org.table.add-col" jetpacs-action-handlers)
                     `((file . ,file) (pos . 1)) nil))
          (let* ((content (with-temp-buffer
                            (insert-file-contents file) (buffer-string)))
                 (lines (cl-remove-if-not
                         (lambda (l) (string-prefix-p "|" l))
                         (split-string content "\n" t))))
            (should (= (length lines) 3))           ; one row appended
            (dolist (l lines)
              (should (= (cl-count ?| l) 4)))       ; one column appended
            ;; The new column landed at the right edge, not the left.
            (should (string-match-p "\\`| a | b |" (car lines)))))
      (delete-file file))))

;; ─── Org babel: emitter and action ──────────────────────────────────────────

(ert-deftest glasspane-org-rich-src-block-run-header ()
  "Executable src blocks with file context grow a run header; others don't."
  (require 'ob-emacs-lisp)
  (let ((body "#+begin_src emacs-lisp\n(+ 1 2)\n#+end_src\n"))
    ;; With context and a loaded language: column of header row + code.
    (let* ((node (car (glasspane-org-rich-body body nil "/tmp/t.org" 10)))
           (kids (alist-get 'children node)))
      (should (equal (alist-get 't node) "column"))
      (let* ((row-kids (alist-get 'children (aref kids 0)))
             (tap (alist-get 'on_tap (aref row-kids 2))))
        (should (equal (alist-get 'text (aref row-kids 0)) "emacs-lisp"))
        (should (equal (alist-get 'action tap) "org.babel.execute"))
        (should (integerp (alist-get 'pos (alist-get 'args tap)))))
      (should (equal (alist-get 't (aref kids 1)) "text")))
    ;; Without file context: plain highlighted code, no affordance.
    (should (equal (alist-get 't (car (glasspane-org-rich-body body nil)))
                   "text"))
    ;; A language this Emacs can't execute: plain code even with context.
    (should (equal (alist-get
                    't (car (glasspane-org-rich-body
                             "#+begin_src nosuchlang\nx\n#+end_src\n"
                             nil "/tmp/t.org" 10)))
                   "text"))))

(ert-deftest glasspane-ui-babel-execute-inserts-results ()
  "The org.babel.execute handler runs the block and saves its RESULTS."
  (require 'ob-emacs-lisp)
  (let ((file (make-temp-file "jetpacs-babel-test" nil ".org"))
        (org-confirm-babel-evaluate nil)
        notified)
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Code\n#+begin_src emacs-lisp\n(+ 1 2)\n#+end_src\n"))
          (let (pos)
            (with-temp-buffer
              (insert-file-contents file)
              (goto-char (point-min))
              (search-forward "#+begin_src")
              (setq pos (line-beginning-position)))
            (cl-letf (((symbol-function 'jetpacs-shell-push) (lambda (&rest _)))
                      ((symbol-function 'jetpacs-shell-notify)
                       (lambda (text) (setq notified text))))
              (funcall (gethash "org.babel.execute" jetpacs-action-handlers)
                       `((file . ,file) (pos . ,pos)) nil)))
          (should (equal notified "Block executed"))
          (let ((content (with-temp-buffer
                           (insert-file-contents file) (buffer-string))))
            (should (string-match-p "#\\+RESULTS:" content))
            (should (string-match-p "^: 3$" content))))
      (delete-file file))))

(ert-deftest glasspane-ui-babel-execute-honors-confirm ()
  "Declining the evaluation prompt aborts: no results, an error snackbar.
Uses org's own non-interactive decline hook
`org-babel-confirm-evaluate-answer-no' so the prompt resolves to \"no\"
deterministically — no stdin, no mocked `yes-or-no-p' (batch Emacs would
otherwise block on the real prompt)."
  (require 'ob-emacs-lisp)
  (let ((file (make-temp-file "jetpacs-babel-test" nil ".org"))
        (org-confirm-babel-evaluate t)
        (org-babel-confirm-evaluate-answer-no t)
        notified)
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+begin_src emacs-lisp\n(+ 1 2)\n#+end_src\n"))
          (cl-letf (((symbol-function 'jetpacs-shell-push) (lambda (&rest _)))
                    ((symbol-function 'jetpacs-shell-notify)
                     (lambda (text) (setq notified text))))
            (funcall (gethash "org.babel.execute" jetpacs-action-handlers)
                     `((file . ,file) (pos . 1)) nil))
          (should (string-prefix-p "Run failed:" (or notified "")))
          (let ((content (with-temp-buffer
                           (insert-file-contents file) (buffer-string))))
            (should-not (string-match-p "#\\+RESULTS:" content))))
      (delete-file file))))

;; ─── Org drawers ─────────────────────────────────────────────────────────────

(defun jetpacs-tests--find-node (tree pred)
  "Depth-first search of widget TREE for a node satisfying PRED.
TREE may be a node (alist), a list of nodes, or a vector of nodes."
  (cond
   ((vectorp tree)
    (cl-some (lambda (x) (jetpacs-tests--find-node x pred)) tree))
   ((and (consp tree) (consp (car tree)) (symbolp (caar tree)))
    (if (funcall pred tree) tree
      (cl-some (lambda (kv) (and (consp kv)
                                 (jetpacs-tests--find-node (cdr kv) pred)))
               tree)))
   ((consp tree)
    (cl-some (lambda (x) (jetpacs-tests--find-node x pred)) tree))))

(ert-deftest glasspane-org-rich-drawer-renders-folded ()
  "Drawers render as collapsed sections instead of disappearing."
  (let* ((nodes (glasspane-org-rich-body
                 ":LOGBOOK:\n- Note taken\n:END:\nBody\n" nil))
         (drawer (car nodes)))
    (should (= (length nodes) 2))       ; drawer + body paragraph
    (should (equal (alist-get 't drawer) "collapsible"))
    (should (eq (alist-get 'collapsed drawer) t))
    (should (equal (alist-get 'text (alist-get 'header drawer)) "LOGBOOK"))
    (should (> (length (alist-get 'children drawer)) 0))))

(ert-deftest glasspane-org-reader-drawer-visibility ()
  "The reader shows heading drawers folded; the detail view (skip-props
path) suppresses the raw LOGBOOK drawer its structured section replaces."
  (let ((file (make-temp-file "jetpacs-drawer-test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Task\n"
                    ":LOGBOOK:\n"
                    "CLOCK: [2026-07-03 Fri 10:00]--[2026-07-03 Fri 11:00] =>  1:00\n"
                    ":END:\n"
                    "Body text\n"))
          (let ((logbook-p (lambda (n)
                             (and (equal (alist-get 't n) "collapsible")
                                  (equal (alist-get 'text (alist-get 'header n))
                                         "LOGBOOK")))))
            (should (jetpacs-tests--find-node
                     (glasspane-org-reader-file file) logbook-p))
            (should-not (jetpacs-tests--find-node
                         (glasspane-org-reader-subtree file 1 t) logbook-p))))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

;; ─── Org case conventions ────────────────────────────────────────────────────
;; Keywords, blocks, and drawer delimiters may be lowercase in org files;
;; TODO keywords and tags are case-sensitive.  Recognition must not depend
;; on the ambient `case-fold-search'.

(ert-deftest glasspane-ui-table-edit-recalculates-lowercase-tblfm ()
  "A lowercase #+tblfm: line is as valid as #+TBLFM: for recalculation."
  (let ((file (make-temp-file "jetpacs-table-test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "| Item   | Qty | Cost |\n"
                    "|--------+-----+------|\n"
                    "| apples |   2 |    4 |\n"
                    "#+tblfm: $3=$2*2\n"))
          (let (pos)
            (with-temp-buffer
              (insert-file-contents file)
              (goto-char (point-min))
              (search-forward "| apples |")
              (setq pos (point)))
            (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "5"))
                      ((symbol-function 'jetpacs-shell-push) (lambda (&rest _)))
                      ((symbol-function 'jetpacs-shell-notify)
                       (lambda (text) (ert-fail text))))
              (funcall (gethash "org.table.edit" jetpacs-action-handlers)
                       `((file . ,file) (pos . ,pos)) nil)))
          (should (string-match-p
                   "| apples | +5 | +10 |"
                   (with-temp-buffer (insert-file-contents file) (buffer-string)))))
      (delete-file file))))

(ert-deftest glasspane-org-lowercase-drawer-and-clock ()
  "Lowercase :logbook:/:end:/clock: parse structurally and render folded."
  ;; Structured logbook parsing (detail view path).
  (with-temp-buffer
    (insert "* Task\n"
            ":logbook:\n"
            "clock: [2026-07-03 Fri 10:00]--[2026-07-03 Fri 11:00] =>  1:00\n"
            ":end:\n")
    (delay-mode-hooks (org-mode))
    (let ((entries (glasspane-ui--logbook-entries 1)))
      (should (= (length entries) 1))
      (should (eq (plist-get (car entries) :type) 'clock))))
  ;; Reader/detail rendering: folded in the reader, suppressed in detail.
  (let ((file (make-temp-file "jetpacs-drawer-test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Task\n:logbook:\n- Note taken\n:end:\nBody\n"))
          (let ((logbook-p (lambda (n)
                             (and (equal (alist-get 't n) "collapsible")
                                  (equal (alist-get 'text (alist-get 'header n))
                                         "logbook")))))
            (should (jetpacs-tests--find-node
                     (glasspane-org-reader-file file) logbook-p))
            (should-not (jetpacs-tests--find-node
                         (glasspane-org-reader-subtree file 1 t) logbook-p))))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

;; ─── Demo org corpus ─────────────────────────────────────────────────────────

(ert-deftest glasspane-demo-org-corpus-is-valid ()
  "The demo org corpus writes, re-writes, parses, and exercises the
rich renderers (native table, babel run button)."
  (require 'ob-emacs-lisp)
  (let ((dir (make-temp-file "glasspane-demo-org" t)))
    (unwind-protect
        (progn
          (glasspane-demo-setup-org dir)
          (glasspane-demo-setup-org dir)  ; overwrite must not error
          (should (= (length glasspane-demo--org-files) 7))
          (dolist (spec glasspane-demo--org-files)
            (should (glasspane-org-reader-file
                     (expand-file-name (car spec) dir))))
          (should (jetpacs-tests--find-node
                   (glasspane-org-reader-file (expand-file-name "health.org" dir))
                   (lambda (n) (equal (alist-get 't n) "table"))))
          (should (jetpacs-tests--find-node
                   (glasspane-org-reader-file (expand-file-name "notes.org" dir))
                   (lambda (n)
                     (equal (alist-get 'action (alist-get 'on_tap n))
                            "org.babel.execute")))))
      (dolist (spec glasspane-demo--org-files)
        (when-let ((buf (find-buffer-visiting
                         (expand-file-name (car spec) dir))))
          (kill-buffer buf)))
      (delete-directory dir t))))

;; ─── App-managed config directory ────────────────────────────────────────────

(ert-deftest glasspane-config-sync-and-ensure ()
  "Managed defaults merge softly; ensure never rewrites an existing dir."
  (let* ((root (make-temp-file "glasspane-config" t))
         (glasspane-config-directory (expand-file-name "managed/" root))
         (org-directory (expand-file-name "org/" root))
         (org-default-notes-file (convert-standard-filename "~/.notes"))
         (org-capture-templates '(("t" "Mine" entry (file "x.org") "* %?")))
         (org-agenda-files nil)
         (org-log-into-drawer nil))
    (unwind-protect
        (progn
          ;; First run: directory missing -> created and loaded.
          (glasspane-config-ensure)
          (should (file-directory-p glasspane-config-directory))
          ;; Soft merge: the user's "t" survives, missing keys append.
          (should (equal "Mine" (nth 1 (assoc "t" org-capture-templates))))
          (should (assoc "n" org-capture-templates))
          (should (assoc "l" org-capture-templates))
          ;; Stock values get seeded with the app's opinions.
          (should (equal org-default-notes-file
                         (expand-file-name "inbox.org" org-directory)))
          (should (equal org-agenda-files (list org-directory)))
          (should org-log-into-drawer)
          ;; Configured values survive a reload untouched.
          (setq org-agenda-files '("/tmp/keep"))
          (glasspane-config-load)
          (should (equal org-agenda-files '("/tmp/keep")))
          ;; `ensure' never rewrites an existing directory; `sync' does.
          (let ((file (expand-file-name "org-defaults.el"
                                        glasspane-config-directory))
                (mangled ";; user mangled\n"))
            (write-region mangled nil file nil 'silent)
            (glasspane-config-ensure)
            (should (equal mangled
                           (with-temp-buffer
                             (insert-file-contents file) (buffer-string))))
            (glasspane-config-sync)
            (should-not (equal mangled
                               (with-temp-buffer
                                 (insert-file-contents file) (buffer-string))))))
      (delete-directory root t))))

;; ─── Widget wire format (golden snapshot) ───────────────────────────────────

(defconst jetpacs-tests--golden-file
  (expand-file-name "widgets.golden" jetpacs-tests--dir))

(defun jetpacs-tests--canon (x)
  "Recursively sort alist keys in X so serialization order is stable."
  (cond
   ((and (consp x) (consp (car x)) (symbolp (caar x)))
    (sort (mapcar (lambda (kv) (cons (car kv) (jetpacs-tests--canon (cdr kv))))
                  (copy-sequence x))
          (lambda (a b) (string< (symbol-name (car a)) (symbol-name (car b))))))
   ((vectorp x) (vconcat (mapcar #'jetpacs-tests--canon x)))
   (t x)))

(defun jetpacs-tests--widget-cases ()
  "A battery exercising every widget constructor with all its options."
  (let* ((act (jetpacs-action "x.y" :args '((k . "v"))
                           :when-offline "drop" :dedupe "d"))
         (leaf (jetpacs-text "leaf")))
    (list
     (jetpacs-text "hi")
     (jetpacs-text "hi" 'title 1 "#FF0000" t 2 4)
     (jetpacs-markup "code" :syntax "elisp" :style 'body :padding 4)
     (jetpacs-rich-text (list (jetpacs-span "a" :bold t)) :style 'body :padding 2)
     (jetpacs-span "s" :bold t :italic t :underline t :strike t :code t
                :tag t :baseline "super" :color "#FFF" :on-tap act :mono t)
     (jetpacs-row leaf leaf)
     (jetpacs-flow-row leaf)
     (jetpacs-column leaf)
     (jetpacs-box (list leaf) :alignment "center" :padding 2 :weight 1 :on-tap act)
     (jetpacs-surface (list leaf) :color "#111" :shape "rounded" :elevation 2 :padding 3)
     (jetpacs-surface (list leaf) :color "surface_container" :shape "rounded_small" :fill t)
     (jetpacs-lazy-column leaf leaf)
     (jetpacs-spacer :height 4 :width 2 :weight 1)
     (jetpacs-divider)
     (jetpacs-card (list leaf) :on-tap act :padding 8 :weight 1)
     (jetpacs-collapsible "cid" leaf (list leaf) :collapsed t :on-long-tap act)
     (jetpacs-reorderable-list (list '((label . "h") (level . 1))) :on-reorder act)
     (jetpacs-action "y.z")
     act
     (jetpacs-clipboard-action "copied text")
     (jetpacs-button "L" act :icon "add" :variant "text" :weight 1 :padding 2)
     (jetpacs-date-button "L" act :value "2026-01-01")
     (jetpacs-time-button "L" act :value "10:00")
     (jetpacs-image "http://x" :content-description "d" :padding 1)
     (jetpacs-icon-button "add" act :content-description "c" :padding 1)
     (jetpacs-menu (list (jetpacs-menu-item "L" act :icon "add")) :icon "more_vert" :padding 2)
     (jetpacs-text-input "tid" :value "v" :hint "h" :label "l" :on-submit act
                      :single-line t :min-lines 1 :max-lines 3
                      :monospace t :syntax "org" :padding 2)
     (jetpacs-text-input "tid2" :multi-line t)
     (jetpacs-enum-list "eid" '("a" "b") :value '("a") :multi-select t
                     :allow-add t :on-change act :padding 1)
     (jetpacs-checkbox "kid" :checked t :label "l" :on-change act :padding 1)
     (jetpacs-switch "sid" :checked t :label "l" :on-change act :padding 1)
     (jetpacs-icon "add" :size 20 :color "#FFF" :padding 1)
     (jetpacs-chip "l" :on-tap act :selected t :icon "add" :padding 1)
     (jetpacs-progress :variant "linear" :value 0.5 :padding 1)
     (jetpacs-assist-chip "l" :on-tap act :icon "add" :padding 1)
     (jetpacs-section-header "t" :trailing leaf :padding 1)
     (jetpacs-empty-state :icon "inbox" :title "t" :caption "c"
                       :on-tap act :action-label "al" :padding 1)
     (jetpacs-date-stamp :date "2026-07-02" :time "10:00" :padding 1)
     (jetpacs-date-stamp :day 2 :month "Jul" :month-index 7 :year 2026)
     (jetpacs-editor "f.org" "content" :on-save act :read-only t :syntax "org"
                  :line-numbers "absolute" :complete t
                  :chromeless t :publish-state t)
     (jetpacs-drawer (list (jetpacs-drawer-item "i" "l" act :selected t)) :header "h")
     (jetpacs-top-bar "t" :nav-icon "menu" :nav-action act :actions (list leaf))
     (jetpacs-fab "add" :label "l" :on-tap act :extended t)
     (jetpacs-bottom-bar (list (jetpacs-nav-item "i" "l" act :selected t)))
     (jetpacs-scaffold :top-bar (jetpacs-top-bar "t") :fab (jetpacs-fab "add")
                    :body leaf :bottom-bar (jetpacs-bottom-bar nil)
                    :snackbar "s" :drawer (jetpacs-drawer nil :header "h")
                    :on-refresh act)
     (jetpacs-table
      (list (jetpacs-table-row
             (list (jetpacs-table-cell (list (jetpacs-span "Item" :bold t)))
                   (jetpacs-table-cell (list (jetpacs-span "Qty"))))
             :header t)
            (jetpacs-table-rule)
            (jetpacs-table-row
             (list (jetpacs-table-cell (list (jetpacs-span "apples"))
                                    :on-tap act :on-long-tap act)
                   (jetpacs-table-cell (list (jetpacs-span "4"))))))
      :aligns '("start" "end") :on-add-row act :on-add-col act :padding 2)
     (jetpacs-table
      (list (jetpacs-table-row (list (jetpacs-table-cell (list (jetpacs-span "a")))))))
     (jetpacs-scroll-row leaf leaf)
     ;; Phase C — composition knobs
     (jetpacs-slider "vol" act :value 0.3 :min 0.0 :max 1.0 :steps 10)
     (jetpacs-row leaf leaf :spacing 4 :align "top")
     (jetpacs-column leaf leaf :spacing 6 :align "center")
     (jetpacs-surface (list leaf) :width 120 :height 40 :fill-fraction 0.5
                   :border (jetpacs-border :width 2 :color "#888"))
     (jetpacs-image "http://x" :width 100 :height 80 :aspect-ratio 1.5
                 :content-scale "crop")
     ;; Phase D — visualization ladder
     (jetpacs-chart (list (jetpacs-chart-series '(1 3 2 5) :label "a" :color "#4C6FFF")
                       (jetpacs-chart-series '(2 2 4 3)))
                 :kind "line" :height 160 :y-range '(0 6) :summary "trend"
                 :on-point-tap act)
     (jetpacs-canvas 100 60
                  (list (jetpacs-draw-line 0 0 100 60 :color "#888" :stroke 2)
                        (jetpacs-draw-rect 10 10 30 20 :fill t :color "primary" :radius 4)
                        (jetpacs-draw-circle 70 30 15 :color "#E64980")
                        (jetpacs-draw-path '((0 60) (50 0) (100 60)) :closed t :fill t)
                        (jetpacs-draw-text 50 30 "hi" :align "center" :size 10))))))

(defun jetpacs-tests--widget-lines ()
  (let ((i -1))
    (mapcar (lambda (c)
              (setq i (1+ i))
              (format "%02d %s" i
                      (json-serialize (jetpacs-tests--canon c)
                                      :null-object :null
                                      :false-object :false)))
            (jetpacs-tests--widget-cases))))

(defun jetpacs-tests-regen-widget-golden ()
  "Rewrite the golden snapshot from the current constructors.
Only run this after an INTENTIONAL wire-format change; review the diff."
  (with-temp-file jetpacs-tests--golden-file
    (insert (string-join (jetpacs-tests--widget-lines) "\n") "\n"))
  (message "Wrote %s" jetpacs-tests--golden-file))

;; ─── Triggers & device capabilities (SPEC §10–§11) ──────────────────────────

(ert-deftest jetpacs-automations-view-renders ()
  "The Automations view builds for both the empty and populated registry."
  (let ((jetpacs-triggers--table (make-hash-table :test 'equal))
        (jetpacs-triggers--last-fired (make-hash-table :test 'equal))
        (jetpacs-triggers-disabled nil))
    (should (jetpacs-automations--view nil))   ; empty state
    (jetpacs-deftrigger test/view
      :type "battery.level" :params '((below . 20))
      :policy "drop" :throttle-s 300 :handler #'ignore)
    (let ((json (json-serialize
                 (jetpacs-tests--canon (jetpacs-automations--view "snack"))
                 :null-object :null :false-object :false)))
      (should (string-search "test/view" json))
      (should (string-search "trigger.toggle" json))
      (should (string-search "trigger.test" json))
      (should (string-search "Never fired" json))
      (should (string-search "below=20" json)))))

;; ─── Spec linter (Phase B / Task 4) ──────────────────────────────────────────

; bogus → error node

(ert-deftest glasspane-gallery-body-lints-clean ()
  "The interactive gallery composes to a wire-valid spec across chart kinds."
  (dolist (glasspane-gallery--kind '("line" "bar" "area" "sparkline"))
    (should-not (jetpacs-lint-spec (glasspane-gallery--body))))
  (dolist (lvl '(0.0 0.5 1.0))
    (should-not (jetpacs-lint-spec (glasspane-gallery--gauge lvl)))))

;; ─── Multi-tenant ownership (Phase E) ─────────────────────────────────────────

;; ─── App identity (jetpacs-defapp, AUTO Task 14) ────────────────────────────────

;; ─── Protocol frame shapes (golden snapshot, SPEC §10–§11) ──────────────────

(defconst jetpacs-tests--frames-golden-file
  (expand-file-name "frames.golden" jetpacs-tests--dir))

(defun jetpacs-tests--device-cases ()
  "One `capability.invoke' payload per `jetpacs-device-*' wrapper.
Captures what each thin defun hands the funnel — the SPEC §10 arg
shapes — without touching the wire."
  (let (calls)
    (cl-letf (((symbol-function 'jetpacs-device--invoke)
               (lambda (cap args &optional _callback)
                 (push `((kind . "capability.invoke")
                         (payload
                          . ((cap . ,cap)
                             (args . ,(or args (make-hash-table
                                                :test 'equal))))))
                       calls))))
      (jetpacs-device-intent :action "android.intent.action.VIEW"
                          :data "https://example.com")
      (jetpacs-device-intent :package "com.termux"
                          :class-name "com.termux.app.TermuxActivity"
                          :mode "activity"
                          :extras '((com.example.FLAG . t)
                                    (com.example.COUNT . 3)))
      (jetpacs-device-app-launch "org.gnu.emacs")
      (jetpacs-device-apps-list #'ignore)
      (jetpacs-device-vibrate 300)
      (jetpacs-device-vibrate nil '(0 100 50 100))
      (jetpacs-device-tts "hello" :pitch 1.2 :rate 0.9)
      (jetpacs-device-volume-set "music" 5)
      (jetpacs-device-ringer-mode "vibrate")
      (jetpacs-device-flashlight t)
      (jetpacs-device-flashlight nil)
      (jetpacs-device-media-key "play_pause")
      (jetpacs-device-clipboard-read #'ignore)
      (jetpacs-device-settings-open "wifi")
      (jetpacs-device-keep-screen-on t)
      (jetpacs-device-brightness 128)
      (jetpacs-device-dnd "priority"))
    (nreverse calls)))

(defun jetpacs-tests--frame-cases ()
  "Outbound protocol frame payloads pinned by test/frames.golden.
Trigger and capability frames today; new wire frames add cases here."
  (let ((jetpacs-triggers--table (make-hash-table :test 'equal)))
    ;; Batch Emacs is disconnected, so these registers never send.
    (jetpacs-trigger-register "power-sync" :type "power"
                           :params '((state . "connected"))
                           :policy "wake" :dedupe "power-sync" :throttle-s 60
                           :on-fire [((cap . "flashlight")
                                      (args . ((on . t))))])
    (jetpacs-trigger-register "screen-off" :type "screen"
                           :params '((state . "off")))
    (append
     (list
      `((kind . "triggers.set")
        (payload . ((triggers . ,(jetpacs-triggers--specs))))))
     (jetpacs-tests--device-cases))))

(defun jetpacs-tests--frame-lines ()
  (let ((i -1))
    (mapcar (lambda (c)
              (setq i (1+ i))
              (format "%02d %s" i
                      (json-serialize (jetpacs-tests--canon c)
                                      :null-object :null
                                      :false-object :false)))
            (jetpacs-tests--frame-cases))))

(defun jetpacs-tests-regen-frame-golden ()
  "Rewrite the frame golden snapshot from the current senders.
Only run this after an INTENTIONAL wire-format change; review the diff."
  (with-temp-file jetpacs-tests--frames-golden-file
    (insert (string-join (jetpacs-tests--frame-lines) "\n") "\n"))
  (message "Wrote %s" jetpacs-tests--frames-golden-file))

;; ─── Journal (PKM Task 5) ────────────────────────────────────────────────────

(ert-deftest glasspane-journal-append-creates-datetree ()
  "First append creates the datetree levels; entries land as list items."
  (let* ((file (make-temp-file "jetpacs-journal" nil ".org"))
         (glasspane-journal-file file)
         (today (glasspane-journal--today)))
    (unwind-protect
        (progn
          (should-not (glasspane-journal--day-pos today))
          (glasspane-journal--append "first thought")
          (glasspane-journal--append "second thought")
          (let ((content (with-temp-buffer
                           (insert-file-contents file) (buffer-string))))
            (should (string-match-p
                     (format "^\\*+[ \t]+%s" (regexp-quote today)) content))
            (should (string-search "- first thought" content))
            (should (string-search "- second thought" content)))
          (should (glasspane-journal--day-pos today))
          ;; The reader renders the day without erroring.
          (should (glasspane-journal--day-nodes today)))
      (delete-file file))))

(ert-deftest glasspane-journal-carried-over ()
  "Unfinished TODOs scheduled before today carry over; done/future don't."
  (let* ((file (make-temp-file "jetpacs-carried" nil ".org"))
         (today (glasspane-journal--today))
         (yesterday (glasspane-ui--shift-date today -1 'day))
         (tomorrow (glasspane-ui--shift-date today 1 'day)))
    (with-temp-file file
      (insert (format "* TODO Old task\nSCHEDULED: <%s>\n" yesterday)
              (format "* DONE Done task\nSCHEDULED: <%s>\n" yesterday)
              (format "* TODO Future task\nSCHEDULED: <%s>\n" tomorrow)))
    (unwind-protect
        (let ((org-agenda-files (list file)))
          (glasspane-org-cache-invalidate)
          (let ((items (glasspane-journal--carried-over)))
            (should (= (length items) 1))
            (should (equal (alist-get 'headline (car items)) "Old task"))
            (should (alist-get 'ref (car items)))))
      (delete-file file))))

(ert-deftest glasspane-journal-actions-drive-state ()
  "nav/goto/today move the viewed date; capture appends and rotates the
input id (the server-driven field clear)."
  (let* ((file (make-temp-file "jetpacs-journal-act" nil ".org"))
         (glasspane-journal-file file)
         (glasspane-journal--date nil)
         (glasspane-journal--capture-gen 0)
         (today (glasspane-journal--today))
         (yesterday (glasspane-ui--shift-date today -1 'day)))
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-shell-push)
                   (cl-function (lambda (&optional _tab &key _switch-to)))))
          (jetpacs--on-action '((action . "journal.nav")
                             (args . ((delta . -1)))) nil)
          (should (equal (glasspane-journal--current) yesterday))
          (jetpacs--on-action '((action . "journal.today")) nil)
          (should (equal (glasspane-journal--current) today))
          (jetpacs--on-action '((action . "journal.goto")
                             (args . ((value . "2026-01-15")))) nil)
          (should (equal (glasspane-journal--current) "2026-01-15"))
          ;; Malformed picker values are ignored.
          (jetpacs--on-action '((action . "journal.goto")
                             (args . ((value . "not-a-date")))) nil)
          (should (equal (glasspane-journal--current) "2026-01-15"))
          ;; Capture with an explicit date lands under that day, trimmed.
          (jetpacs--on-action '((action . "journal.capture")
                             (args . ((value . "  typed on phone  ")
                                      (date . "2026-01-15")))) nil)
          (should (= glasspane-journal--capture-gen 1))
          (let ((content (with-temp-buffer
                           (insert-file-contents file) (buffer-string))))
            (should (string-search "- typed on phone" content))
            (should (string-match-p "^\\*+[ \t]+2026-01-15" content)))
          ;; Leaving the journal resets the viewed date to today.
          (glasspane-journal--on-view-switched "agenda")
          (should (equal (glasspane-journal--current) today)))
      (delete-file file))))

(ert-deftest glasspane-journal-view-renders ()
  "The journal view builds with day content + the carried-over section."
  (let* ((file (make-temp-file "jetpacs-journal-view" nil ".org"))
         (agenda (make-temp-file "jetpacs-journal-agenda" nil ".org"))
         (glasspane-journal-file file)
         (glasspane-journal--date nil)
         (today (glasspane-journal--today))
         (yesterday (glasspane-ui--shift-date today -1 'day)))
    (with-temp-file agenda
      (insert (format "* TODO Carry me\nSCHEDULED: <%s>\n" yesterday)))
    (unwind-protect
        (let ((org-agenda-files (list agenda)))
          (glasspane-org-cache-invalidate)
          (glasspane-journal--append "a journal line")
          (let ((json (json-serialize
                       (jetpacs-tests--canon (glasspane-journal--view nil))
                       :null-object :null :false-object :false)))
            (should (string-search "journal-capture-" json))
            (should (string-search "a journal line" json))
            (should (string-search "Carried over (1)" json))
            (should (string-search "Carry me" json))
            (should (string-search "heading.schedule" json))
            (should (string-search "journal.capture" json))))
      (delete-file file)
      (delete-file agenda))))

;; ─── Saved views (PKM Task 11) ───────────────────────────────────────────────

(defun jetpacs-tests--views-items ()
  "Synthetic heading items exercising all three renderings."
  '(((headline . "Write spec") (todo . "TODO") (tags . ["work"])
     (scheduled . "<2026-07-04 Sat>")
     (ref . ((file . "/tmp/a.org") (pos . 1) (headline . "Write spec"))))
    ((headline . "Ship it") (todo . "NEXT") (tags . [])
     (scheduled . nil)
     (ref . ((file . "/tmp/a.org") (pos . 50) (headline . "Ship it"))))))

(ert-deftest glasspane-views-renderings-build ()
  "Table, board, and calendar renderings build from the same items."
  (let ((items (jetpacs-tests--views-items))
        (org-todo-keywords-1 '("TODO" "NEXT" "DONE")))
    (let ((json (json-serialize (jetpacs-tests--canon
                                 (glasspane-views--table-node items))
                                :null-object :null :false-object :false)))
      (should (string-search "Write spec" json))
      (should (string-search "2026-07-04" json))
      (should (string-search "heading.tap" json)))
    (let ((json (json-serialize (jetpacs-tests--canon
                                 (glasspane-views--board-node items))
                                :null-object :null :false-object :false)))
      ;; Column per present state, keyword order; menu moves between them.
      (should (string-search "TODO (1)" json))
      (should (string-search "NEXT (1)" json))
      (should (string-search "heading.todo-set" json)))
    (let ((json (json-serialize (jetpacs-tests--canon
                                 (apply #'jetpacs-column
                                        (glasspane-views--calendar-nodes items)))
                                :null-object :null :false-object :false)))
      (should (string-search "Unscheduled" json))
      (should (string-search "Ship it" json)))))

(ert-deftest glasspane-views-board-includes-file-local-keywords ()
  "A TODO state the global keyword list doesn't know still gets a
column — cards with file-local #+TODO: keywords must not silently
vanish from the board."
  (let ((org-todo-keywords-1 '("TODO" "DONE"))
        (items '(((headline . "Global") (todo . "TODO")
                  (ref . ((file . "/tmp/a.org") (pos . 1))))
                 ((headline . "Waiting on Bob") (todo . "WAIT")
                  (ref . ((file . "/tmp/b.org") (pos . 1))))
                 ((headline . "Stateless")
                  (ref . ((file . "/tmp/b.org") (pos . 9)))))))
    (should (equal (glasspane-views--board-columns items)
                   '("TODO" "WAIT" "")))
    (let ((json (json-serialize (jetpacs-tests--canon
                                 (glasspane-views--board-node items))
                                :null-object :null :false-object :false)))
      (should (string-search "WAIT (1)" json))
      (should (string-search "Waiting on Bob" json)))))

(ert-deftest glasspane-views-save-open-delete ()
  "The save/open/rendering/delete lifecycle over the UI-state store."
  (let ((glasspane-saved-views nil)
        (glasspane-views--current nil)
        (glasspane-views--form-gen 0)
        (jetpacs--ui-state (make-hash-table :test 'equal))
        (persisted 0))
    (cl-letf (((symbol-function 'jetpacs-settings-save-variable)
               (lambda (_sym _val) (cl-incf persisted) t))
              ((symbol-function 'jetpacs-shell-push)
               (cl-function (lambda (&optional _tab &key _switch-to)))))
      ;; Save from the form fields.
      (jetpacs-ui-state-put "views-new-name-0" "Work")
      (jetpacs-ui-state-put "views-new-query-0" "todo:TODO tags:work")
      (jetpacs-ui-state-put "views-new-rendering-0" "board")
      (jetpacs--on-action '((action . "views.save")) nil)
      (should (= (length glasspane-saved-views) 1))
      (should (= glasspane-views--form-gen 1))   ; field-clearing id rotation
      (should (= persisted 1))
      (let ((view (glasspane-views--get "Work")))
        (should (equal (alist-get 'query view) "todo:TODO tags:work"))
        (should (equal (alist-get 'rendering view) "board")))
      ;; A malformed query is refused at save time.
      (jetpacs-ui-state-put "views-new-name-1" "Broken")
      (jetpacs-ui-state-put "views-new-query-1" "(todo \"TODO\"")
      (jetpacs--on-action '((action . "views.save")) nil)
      (should (= (length glasspane-saved-views) 1))
      ;; Open / switch rendering / delete.
      (jetpacs--on-action '((action . "views.open") (args . ((name . "Work")))) nil)
      (should (equal glasspane-views--current "Work"))
      (jetpacs--on-action '((action . "views.rendering")
                         (args . ((name . "Work") (rendering . "calendar")))) nil)
      (should (equal (alist-get 'rendering (glasspane-views--get "Work"))
                     "calendar"))
      (jetpacs--on-action '((action . "views.delete") (args . ((name . "Work")))) nil)
      (should-not glasspane-saved-views)
      (should-not glasspane-views--current))))

(ert-deftest glasspane-views-rendering-on-bare-entry ()
  "views.rendering works on a hand-authored entry without a
`rendering' key (the `repeat sexp' Customize type invites those) —
the list is rebuilt, never mutated in place."
  (let ((glasspane-saved-views '(((name . "Bare") (query . "todo:TODO"))))
        (persisted 0))
    (cl-letf (((symbol-function 'jetpacs-settings-save-variable)
               (lambda (_sym _val) (cl-incf persisted) t))
              ((symbol-function 'jetpacs-shell-push)
               (cl-function (lambda (&optional _tab &key _switch-to)))))
      (jetpacs--on-action '((action . "views.rendering")
                         (args . ((name . "Bare") (rendering . "board"))))
                       nil)
      (should (equal (alist-get 'rendering (glasspane-views--get "Bare"))
                     "board"))
      (should (equal (alist-get 'query (glasspane-views--get "Bare"))
                     "todo:TODO"))
      (should (= persisted 1)))))

(ert-deftest glasspane-views-end-to-end-render ()
  "A saved view renders real query results from an agenda file."
  (let* ((agenda (make-temp-file "jetpacs-views" nil ".org"))
         (glasspane-saved-views
          '(((name . "Work") (query . "todo:TODO") (rendering . "list"))))
         (glasspane-views--current "Work"))
    (with-temp-file agenda
      (insert "* TODO Alpha :work:\nSCHEDULED: <2026-07-04 Sat>\n"
              "* DONE Omega\n"))
    (unwind-protect
        (let ((org-agenda-files (list agenda)))
          (glasspane-org-cache-invalidate)
          (let ((json (json-serialize
                       (jetpacs-tests--canon (glasspane-views--view nil))
                       :null-object :null :false-object :false)))
            (should (string-search "Alpha" json))
            (should-not (string-search "Omega" json))
            (should (string-search "views.rendering" json))
            (should (string-search "views.back" json))))
      (delete-file agenda))))

;; ─── Org-defined automations (AUTO Task 13) ──────────────────────────────────

(defmacro jetpacs-tests--with-automations-file (content &rest body)
  "Run BODY with a temp automations file holding CONTENT."
  (declare (indent 1))
  `(let* ((file (make-temp-file "jetpacs-autom" nil ".org"))
          (glasspane-automations-file file)
          (glasspane-automations--ids nil)
          (jetpacs-triggers--table (make-hash-table :test 'equal))
          (jetpacs-triggers-changed-hook nil))
     (unwind-protect
         (progn (with-temp-file file (insert ,content))
                ,@body)
       (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
       (delete-file file))))

(ert-deftest glasspane-automations-parses-rules ()
  "Headings with :TRIGGER: become registrations; DONE disables; the
lowercase drawer parses (org case conventions)."
  (jetpacs-tests--with-automations-file
      (concat "* Charge sync\n"
              ":PROPERTIES:\n:TRIGGER: power connected\n:POLICY: wake\n"
              ":THROTTLE: 300\n:END:\n"
              "#+begin_src elisp\n(setq jetpacs-tests--autom-fired data)\n#+end_src\n"
              ;; Case conventions: lowercase drawer + property + block.
              "* Low battery\n"
              ":properties:\n:trigger: battery.level below 20\n:end:\n"
              "#+begin_src emacs-lisp\n(ignore)\n#+end_src\n"
              "* DONE Old rule\n"
              ":PROPERTIES:\n:TRIGGER: screen off\n:END:\n"
              "* Not a rule\nJust some notes.\n"
              "* Bad type\n"
              ":PROPERTIES:\n:TRIGGER: warp.drive on\n:END:\n"
              ;; Hardware-gated, not shipped: must be skipped, or its
              ;; presence would poison the whole replace-set companion-side.
              "* Home wifi\n"
              ":PROPERTIES:\n:TRIGGER: wifi.ssid connected\n:END:\n")
    (let ((ids (glasspane-automations-reload)))
      (should (equal (sort (copy-sequence ids) #'string<)
                     '("org/Charge sync" "org/Low battery")))
      (let ((reg (gethash "org/Charge sync" jetpacs-triggers--table)))
        (should (equal (plist-get reg :type) "power"))
        (should (equal (plist-get reg :params) '((state . "connected"))))
        (should (equal (plist-get reg :policy) "wake"))
        (should (= (plist-get reg :throttle-s) 300))
        (should (functionp (plist-get reg :handler))))
      (let ((reg (gethash "org/Low battery" jetpacs-triggers--table)))
        (should (equal (plist-get reg :type) "battery.level"))
        (should (equal (plist-get reg :params) '((below . 20)))))
      ;; DONE and unknown/unshipped-type rules never registered.
      (should-not (gethash "org/Old rule" jetpacs-triggers--table))
      (should-not (gethash "org/Bad type" jetpacs-triggers--table))
      (should-not (gethash "org/Home wifi" jetpacs-triggers--table)))))

(ert-deftest glasspane-automations-handler-runs-and-reload-replaces ()
  "The src-block handler fires with `data' in scope; a reload drops
rules that left the file."
  (defvar jetpacs-tests--autom-fired nil)
  (jetpacs-tests--with-automations-file
      (concat "* Charge sync\n"
              ":PROPERTIES:\n:TRIGGER: power connected\n:END:\n"
              "#+begin_src elisp\n(setq jetpacs-tests--autom-fired data)\n#+end_src\n")
    (glasspane-automations-reload)
    (setq jetpacs-tests--autom-fired nil)
    (jetpacs-trigger-test-fire "org/Charge sync")
    ;; Test fires carry no data payload; args reached the handler.
    (should (gethash "org/Charge sync" jetpacs-triggers--last-fired))
    ;; Simulate a real fire with data.
    (jetpacs-triggers--on-fired
     '((id . "org/Charge sync") (type . "power")
       (data . ((state . "connected"))) (at_ms . 1))
     nil)
    (should (equal (alist-get 'state jetpacs-tests--autom-fired) "connected"))
    ;; Rewrite the file without the rule: reload unregisters it.
    (with-temp-file file (insert "* Nothing here\n"))
    (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
    (should-not (glasspane-automations-reload))
    (should-not (gethash "org/Charge sync" jetpacs-triggers--table))))

;; ─── Sparse filter (orgro parity) ────────────────────────────────────────────

(ert-deftest glasspane-sparse-filter-narrows-headings ()
  "The read-mode filter narrows by query; clearing restores; bad
queries surface instead of blanking the file."
  (let* ((file (make-temp-file "jetpacs-sparse" nil ".org"))
         (glasspane-ui--files-read-mode t)
         (glasspane-ui--files-refile-mode nil)
         (glasspane-ui--files-filter ""))
    (with-temp-file file
      (insert "* TODO Pay taxes :money:\n"
              "* TODO Water plants :home:\n"
              "* Reference notes\nSome body text about taxes.\n"))
    (unwind-protect
        (progn
          ;; Unfiltered: all three headings render.
          (let ((json (json-serialize
                       (jetpacs-tests--canon (glasspane-ui--org-editor-body file))
                       :null-object :null :false-object :false)))
            (should (string-search "Pay taxes" json))
            (should (string-search "Water plants" json))
            (should (string-search "files.filter" json)))
          ;; Tag filter.
          (let* ((glasspane-ui--files-filter "tags:money")
                 (json (json-serialize
                        (jetpacs-tests--canon (glasspane-ui--org-editor-body file))
                        :null-object :null :false-object :false)))
            (should (string-search "Pay taxes" json))
            (should-not (string-search "Water plants" json))
            (should (string-search "1 of 3 headings" json)))
          ;; Free text matches bodies too.
          (let* ((glasspane-ui--files-filter "taxes")
                 (json (json-serialize
                        (jetpacs-tests--canon (glasspane-ui--org-editor-body file))
                        :null-object :null :false-object :false)))
            (should (string-search "Pay taxes" json))
            (should (string-search "Reference notes" json))
            (should-not (string-search "Water plants" json)))
          ;; A query with unbalanced parens degrades to a message.
          (let* ((glasspane-ui--files-filter "(todo \"TODO\"")
                 (json (json-serialize
                        (jetpacs-tests--canon (glasspane-ui--org-editor-body file))
                        :null-object :null :false-object :false)))
            (should (string-search "unbalanced" json))))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

(ert-deftest glasspane-sparse-filter-action-sets-state ()
  "files.filter stores the query; opening another file resets it."
  (let ((glasspane-ui--files-filter ""))
    (cl-letf (((symbol-function 'jetpacs-shell-push)
               (cl-function (lambda (&optional _tab &key _switch-to)))))
      (jetpacs--on-action '((action . "files.filter")
                         (args . ((value . "todo:TODO")))) nil)
      (should (equal glasspane-ui--files-filter "todo:TODO"))
      (run-hook-with-args 'jetpacs-files-open-hook "/tmp/other.org")
      (should (equal glasspane-ui--files-filter "")))))

;; ─── Notes bridge: wikilinks + backlinks (PKM 3–4, vulpea mocked) ────────────

(defmacro jetpacs-tests--with-fake-vulpea (notes &rest body)
  "Run BODY with the vulpea seam answering from NOTES (plists)."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'glasspane-notes-available-p) (lambda () t))
             ((symbol-function 'vulpea-db-search-by-title)
              (lambda (pattern)
                (cl-remove-if-not
                 (lambda (n) (string-match-p (regexp-quote (downcase pattern))
                                             (downcase (plist-get n :title))))
                 ,notes)))
             ((symbol-function 'vulpea-db-query-by-links-some)
              (lambda (_ids &optional _type) ,notes))
             ((symbol-function 'vulpea-db-get-by-id)
              (lambda (id)
                (cl-find id ,notes
                         :key (lambda (n) (plist-get n :id))
                         :test #'equal)))
             ((symbol-function 'vulpea-note-id)
              (lambda (n) (plist-get n :id)))
             ((symbol-function 'vulpea-note-title)
              (lambda (n) (plist-get n :title)))
             ((symbol-function 'vulpea-note-path)
              (lambda (n) (plist-get n :path)))
             ((symbol-function 'vulpea-note-aliases)
              (lambda (n) (plist-get n :aliases))))
     ,@body))

(ert-deftest glasspane-notes-wikilink-completion ()
  "Typing [[pa in an org shadow buffer offers notes; accepting inserts
a full id link via the candidate `insert' attr."
  (jetpacs-tests--with-fake-vulpea
      '((:id "abc-1" :title "Paris trip" :path "/v/paris.org")
        (:id "abc-2" :title "Pasta recipes" :path "/v/pasta.org"))
    (let ((result (jetpacs-complete-in-text "wiki-test.org" "see [[pa" 8)))
      (should result)
      (should (equal (car result) "[[pa"))
      (let ((cand (cl-find "[[Paris trip" (cdr result)
                           :key (lambda (c) (alist-get 'label c))
                           :test #'equal)))
        (should cand)
        (should (equal (alist-get 'insert cand) "[[id:abc-1][Paris trip]]"))
        (should (equal (alist-get 'annotation cand) "paris.org"))))
    ;; Outside brackets the org capf stays silent (word fallback rules).
    (let ((result (jetpacs-complete-in-text "wiki-test.org" "plain pa" 8)))
      (should-not (cl-find-if (lambda (c)
                                (string-prefix-p "[[" (alist-get 'label c)))
                              (cdr result))))))

(ert-deftest glasspane-notes-backlink-section ()
  "The detail section lists linked references and the mentions button."
  (jetpacs-tests--with-fake-vulpea
      '((:id "src-1" :title "Travel log" :path "/v/log.org"))
    (let* ((glasspane-notes--mentions (make-hash-table :test 'equal))
           (nodes (glasspane-notes-detail-nodes '((id . "abc-1"))))
           (json (json-serialize (jetpacs-tests--canon (apply #'jetpacs-column nodes))
                                 :null-object :null :false-object :false)))
      (should (string-search "Linked references (1)" json))
      (should (string-search "Travel log" json))
      (should (string-search "notes.mentions" json))
      ;; The backlink card opens the referenced heading in the detail
      ;; view (`heading.tap'), not the raw file.
      (should (string-search "heading.tap" json)))
    ;; No id in the ref → no section at all.
    (should-not (glasspane-notes-detail-nodes '((file . "/v/x.org"))))))

(ert-deftest glasspane-notes-ref-id-resolves-from-heading ()
  "A reader-built ref (file/pos, no id) still finds the heading's :ID:,
so drilled-into child headings get their backlink section."
  (let ((file (make-temp-file "jetpacs-refid" nil ".org")))
    (with-temp-file file
      (insert "* Parent\n** Child heading\n:PROPERTIES:\n"
              ":ID: child-id-42\n:END:\nBody.\n"))
    (unwind-protect
        (let ((pos (with-current-buffer (find-file-noselect file)
                     (org-with-wide-buffer
                      (goto-char (point-min))
                      (search-forward "** Child")
                      (line-beginning-position)))))
          (should (equal (glasspane-notes--ref-id
                          `((file . ,file) (pos . ,pos)
                            (headline . "Child heading")))
                         "child-id-42"))
          ;; And a ref that already carries the id short-circuits.
          (should (equal (glasspane-notes--ref-id '((id . "direct")))
                         "direct")))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

(ert-deftest glasspane-notes-mention-card-path-from-note ()
  "Mention cards take the path from the mentioning note — vulpea's
resolve plists don't reliably carry :path."
  (jetpacs-tests--with-fake-vulpea nil
    (let ((json (json-serialize
                 (jetpacs-tests--canon
                  (glasspane-notes--mention-card
                   '(:note (:id "src" :title "Source note" :path "/v/src.org")
                     :line 7 :context "the mention line" :matched "Target")
                   "target-id"))
                 :null-object :null :false-object :false)))
      (should (string-search "/v/src.org" json))
      (should (string-search "link.materialize" json))
      (should (string-search "\"line\":7" json)))))

(ert-deftest glasspane-demo-link-graph-consistent ()
  "The demo corpus's id links resolve to real :ID: properties, and the
unlinked-mention fixtures ('Babel playground', 'Grace Hopper') appear
as plain text — the on-device backlink checks depend on this graph."
  (let ((ids nil) (targets nil))
    (dolist (entry glasspane-demo--org-files)
      (let ((content (cdr entry)) (pos 0))
        (while (string-match ":ID:[ \t]+\\([0-9a-f-]+\\)" content pos)
          (push (match-string 1 content) ids)
          (setq pos (match-end 0)))
        (setq pos 0)
        (while (string-match "\\[\\[id:\\([0-9a-f-]+\\)\\]" content pos)
          (push (match-string 1 content) targets)
          (setq pos (match-end 0)))))
    (should (>= (length targets) 3))
    (dolist (target targets)
      (should (member target ids))))
  (let ((project (cdr (assoc "project.org" glasspane-demo--org-files)))
        (notes (cdr (assoc "notes.org" glasspane-demo--org-files))))
    ;; Mentions must be plain text, not links.
    (should (string-search "Babel playground over" project))
    (should (string-search "Grace Hopper would" notes))))

(ert-deftest glasspane-notes-materialize-links-mention ()
  "link.materialize rewrites the mention line into a real id link."
  (let ((file (make-temp-file "jetpacs-mention" nil ".org")))
    (with-temp-file file
      (insert "* Notes\nWe talked about paris trip plans today.\n"))
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-shell-push)
                   (cl-function (lambda (&optional _tab &key _switch-to)))))
          (jetpacs--on-action
           `((action . "link.materialize")
             (args . ((id . "abc-1") (path . ,file) (line . 2)
                      (matched . "Paris trip"))))
           nil)
          (let ((content (with-temp-buffer
                           (insert-file-contents file) (buffer-string))))
            ;; Case-insensitive find, file's own casing preserved.
            (should (string-search "[[id:abc-1][paris trip]]" content))))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

(ert-deftest glasspane-notes-materialize-without-matched ()
  "link.materialize works from a real-shaped vulpea mention plist.
Current vulpea resolve plists carry no :matched, so the action falls
back to the note's title and aliases; occurrences already inside a
link are skipped (the double-link guard)."
  (let ((file (make-temp-file "jetpacs-mention" nil ".org")))
    (with-temp-file file
      (insert "* Notes\n"
              "See [[id:abc-1][Paris trip]] and our paris trip plans.\n"
              "The city of light features often.\n"))
    (unwind-protect
        (jetpacs-tests--with-fake-vulpea
            '((:id "abc-1" :title "Paris trip" :path "/v/paris.org"
                    :aliases ("City of Light")))
          (cl-letf (((symbol-function 'jetpacs-shell-push)
                     (cl-function (lambda (&optional _tab &key _switch-to)))))
            ;; Line 2: the already-linked occurrence must be skipped;
            ;; the plain one after it gets the link.
            (jetpacs--on-action
             `((action . "link.materialize")
               (args . ((id . "abc-1") (path . ,file) (line . 2))))
             nil)
            ;; Line 3: no title on the line — the alias matches.
            (jetpacs--on-action
             `((action . "link.materialize")
               (args . ((id . "abc-1") (path . ,file) (line . 3))))
             nil)
            (let ((content (with-temp-buffer
                             (insert-file-contents file) (buffer-string))))
              (should (string-search "See [[id:abc-1][Paris trip]] and"
                                     content))
              (should (string-search "[[id:abc-1][paris trip]] plans"
                                     content))
              (should (string-search "[[id:abc-1][city of light]] features"
                                     content)))))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

;; ─── SRS skin: review over org-srs (org-srs mocked) ──────────────────────────

(defvar jetpacs-tests--srs-items nil "The mocked pending queue (item-args).")
(defvar jetpacs-tests--srs-rated nil "Ratings recorded by the mock engine.")

(defmacro jetpacs-tests--with-fake-org-srs (&rest body)
  "Run BODY with a minimal org-srs *engine* mock.
`jetpacs-tests--srs-items' is the pending queue (a list of item-args);
`jetpacs-tests--srs-rated' records ratings.  Session state is reset per
invocation; per-item positions (markers, regions, clozes) are mocked
in individual tests where needed."
  (declare (indent 0))
  `(let ((glasspane-srs--available t)
         (glasspane-srs--active nil)
         (glasspane-srs--current nil)
         (glasspane-srs--revealed nil)
         (glasspane-srs--undo nil)
         (jetpacs-tests--srs-items nil)
         (jetpacs-tests--srs-rated nil)
         (jetpacs-shell--snackbar nil))
     (cl-letf (((symbol-function 'org-srs-review-pending-items)
                (lambda (&optional _) jetpacs-tests--srs-items))
               ((symbol-function 'org-srs-item-marker)
                (lambda (&rest _) (copy-marker (point-min))))
               ((symbol-function 'org-srs-review-rate)
                (lambda (rating &rest _) (push rating jetpacs-tests--srs-rated)))
               ((symbol-function 'org-srs-item-call-with-current)
                (lambda (thunk &rest _) (funcall thunk)))
               ((symbol-function 'org-srs-table-goto-column)
                (lambda (_) t))
               ((symbol-function 'org-srs-stats-intervals)
                (lambda () '(:again 600 :hard 86400 :good 259200 :easy 604800)))
               ((symbol-function 'org-srs-time-seconds-desc)
                (lambda (secs) (list (/ secs 60) :minute)))
               ((symbol-function 'jetpacs-shell-push)
                (cl-function (lambda (&optional _tab &key _switch-to)))))
       ,@body)))

(ert-deftest glasspane-srs-idle-view ()
  "Between sessions the view shows the due count and the start button;
zero due shows the caught-up empty state."
  (jetpacs-tests--with-fake-org-srs
    (glasspane-org-cache-invalidate)
    (let* ((jetpacs-tests--srs-items '(a b c))
           (json (json-serialize
                  (jetpacs-tests--canon (glasspane-srs--view nil))
                  :null-object :null :false-object :false)))
      (should (string-search "3 items due" json))
      (should (string-search "srs.review.start" json)))
    (glasspane-org-cache-invalidate)
    (let* ((jetpacs-tests--srs-items nil)
           (json (json-serialize
                  (jetpacs-tests--canon (glasspane-srs--view nil))
                  :null-object :null :false-object :false)))
      (should (string-search "All caught up" json)))))

(ert-deftest glasspane-srs-card-clean-multiline-answer ()
  "A card whose answer is a multi-line body renders the clean question
title (no stars) with the answer omitted until revealed — and NO stray
ellipsis dots (the on-device bug where each wrapped answer line showed
its own `...')."
  (jetpacs-tests--with-fake-org-srs
    (with-temp-buffer
      (org-mode)
      ;; A real entry, including org-srs's own drawers, so plain-org meta
      ;; skipping is exercised (no card-region mocks).
      (insert "* What does the Gaussian integral evaluate to?\n"
              ":PROPERTIES:\n:ID: gauss\n:END:\n"
              ":SRSITEMS:\n#+NAME: srsitem:gauss::card::back\n| ! | ts |\n:END:\n"
              "√π — a multi-line\nanswer body that\nwraps across lines.\n")
      (let ((buf (current-buffer)))
        (cl-letf (((symbol-function 'org-srs-item-marker)
                   (lambda (&rest _) (copy-marker (point-min)))))
          (let ((q (json-serialize
                    (jetpacs-tests--canon
                     (apply #'jetpacs-column
                            (glasspane-srs--item-nodes '((card back) "gauss" buf) nil)))
                    :null-object :null :false-object :false)))
            (should (string-search "Gaussian integral" q))
            (should-not (string-search "answer body" q))
            (should-not (string-search "..." q))
            (should-not (string-search "* What" q))     ; star dropped
            (should-not (string-search "SRSITEMS" q)))  ; drawer skipped
          (let ((a (json-serialize
                    (jetpacs-tests--canon
                     (apply #'jetpacs-column
                            (glasspane-srs--item-nodes '((card back) "gauss" buf) t)))
                    :null-object :null :false-object :false)))
            (should (string-search "answer body" a))
            (should (string-search "wraps across lines" a))
            (should-not (string-search "..." a))
            (should-not (string-search "SRSITEMS" a))
            ;; Flashcard prose renders proportional, not monospace.
            (should-not (string-search "mono" a))))))))

(ert-deftest glasspane-srs-card-frontback-excises-and-strips ()
  "A Front/Back card shows only the question until revealed; the
revealed answer is the Back child's body, without its heading line."
  (jetpacs-tests--with-fake-org-srs
    (with-temp-buffer
      (org-mode)
      (insert "* Term\n:PROPERTIES:\n:ID: t\n:END:\n"
              "Question text here.\n** Back\nThe answer text.\n")
      (let ((buf (current-buffer)))
        (cl-letf (((symbol-function 'org-srs-item-marker)
                   (lambda (&rest _) (copy-marker (point-min)))))
          (let ((q (json-serialize
                    (jetpacs-tests--canon
                     (apply #'jetpacs-column
                            (glasspane-srs--item-nodes '((card back) "t" buf) nil)))
                    :null-object :null :false-object :false)))
            (should (string-search "Question text" q))
            (should-not (string-search "answer text" q))
            (should-not (string-search "Back" q)))
          (let ((a (json-serialize
                    (jetpacs-tests--canon
                     (apply #'jetpacs-column
                            (glasspane-srs--item-nodes '((card back) "t" buf) t)))
                    :null-object :null :false-object :false)))
            (should (string-search "answer text" a))
            (should-not (string-search "Back" a))))))))   ; heading line stripped

(ert-deftest glasspane-srs-cloze-blank-then-reveal ()
  "A cloze renders the sentence with the reviewed span blanked and the
other cloze's text as context; revealing shows the answer.  Only
`org-srs-item-cloze-collect' is mocked — bounds come from plain org."
  (jetpacs-tests--with-fake-org-srs
    (with-temp-buffer
      (org-mode)
      (insert "* The first computer bug\n:PROPERTIES:\n:ID: bug\n:END:\n"
              "operators taped {{h1}{a moth}} into the log in {{h2}{1947}}.\n")
      (let* ((buf (current-buffer))
             (c1 (progn (goto-char (point-min))
                        (search-forward "{{h1}{a moth}}")
                        (list 'h1 (match-beginning 0) (match-end 0) "a moth")))
             (c2 (progn (goto-char (point-min))
                        (search-forward "{{h2}{1947}}")
                        (list 'h2 (match-beginning 0) (match-end 0) "1947"))))
        (cl-letf (((symbol-function 'org-srs-item-marker)
                   (lambda (&rest _) (copy-marker (point-min))))
                  ((symbol-function 'org-srs-item-cloze-collect)
                   (lambda (&rest _) (list c1 c2))))
          (let ((q (json-serialize
                    (jetpacs-tests--canon
                     (apply #'jetpacs-column
                            (glasspane-srs--item-nodes '((cloze h1) "bug" buf) nil)))
                    :null-object :null :false-object :false)))
            (should (string-search "operators taped" q))
            (should (string-search "1947" q))          ; other cloze = context
            (should-not (string-search "a moth" q))    ; reviewed = blanked
            (should (string-search "[" q)))
          (let ((a (json-serialize
                    (jetpacs-tests--canon
                     (apply #'jetpacs-column
                            (glasspane-srs--item-nodes '((cloze h1) "bug" buf) t)))
                    :null-object :null :false-object :false)))
            (should (string-search "a moth" a))))))))

(ert-deftest glasspane-srs-flow-advances ()
  "The self-managed loop: start loads the first pending item; Show
answer is a pure flag (no confirm call); rating records and advances to
the next pending item; an unknown rating is ignored; a drained queue
lands on the done state; quit clears."
  (jetpacs-tests--with-fake-org-srs
    (let ((confirm-touched nil))
      (cl-letf (((symbol-function 'org-srs-item-confirm-command)
                 (lambda (&rest _) (setq confirm-touched t)))
                ((symbol-function 'org-srs-item-confirm-pending-p)
                 (lambda (&rest _) (setq confirm-touched t) nil)))
        (setq jetpacs-tests--srs-items '(((card back) "a" nil) ((card back) "b" nil)))
        (jetpacs--on-action '((action . "srs.review.start")) nil)
        (should glasspane-srs--active)
        (should (equal glasspane-srs--current '((card back) "a" nil)))
        (should-not glasspane-srs--revealed)
        ;; Show answer: pure UI flag, no org-srs confirm machinery touched.
        (jetpacs--on-action '((action . "srs.answer.show")) nil)
        (should glasspane-srs--revealed)
        (should-not confirm-touched)
        ;; Rate: records, advances to the next pending item.
        (setq jetpacs-tests--srs-items '(((card back) "b" nil)))
        (jetpacs--on-action '((action . "srs.rate") (args . ((rating . "good")))) nil)
        (should (equal jetpacs-tests--srs-rated '(:good)))
        (should (equal glasspane-srs--current '((card back) "b" nil)))
        (should-not glasspane-srs--revealed)
        ;; Unknown rating: ignored.
        (jetpacs--on-action '((action . "srs.rate") (args . ((rating . "meh")))) nil)
        (should (equal jetpacs-tests--srs-rated '(:good)))
        ;; Queue drains → done state (active, no current); quit clears.
        (setq jetpacs-tests--srs-items nil)
        (jetpacs--on-action '((action . "srs.rate") (args . ((rating . "easy")))) nil)
        (should (equal jetpacs-tests--srs-rated '(:easy :good)))
        (should-not glasspane-srs--current)
        (should glasspane-srs--active)
        (jetpacs--on-action '((action . "srs.quit")) nil)
        (should-not glasspane-srs--active)))))

(ert-deftest glasspane-srs-rate-in-item-buffer ()
  "srs.rate makes the item's buffer current before calling
`org-srs-review-rate'.  org-srs reads a session-local schedule offset
from `(current-buffer)', so rating from the wrong buffer errors and the
card never reschedules — the on-device loop."
  (jetpacs-tests--with-fake-org-srs
    (with-temp-buffer
      (let ((item-buf (current-buffer))
            (seen-buf nil))
        (cl-letf (((symbol-function 'org-srs-item-marker)
                   (lambda (&rest _)
                     (with-current-buffer item-buf (copy-marker (point-min)))))
                  ((symbol-function 'org-srs-review-rate)
                   (lambda (rating &rest _)
                     (setq seen-buf (current-buffer))
                     (push rating jetpacs-tests--srs-rated))))
          ;; Drive the action from a DIFFERENT buffer than the item's.
          (with-temp-buffer
            (setq glasspane-srs--active t
                  glasspane-srs--current (list '(card back) "id" item-buf)
                  glasspane-srs--revealed t)
            (jetpacs--on-action
             '((action . "srs.rate") (args . ((rating . "good")))) nil))
          (should (equal jetpacs-tests--srs-rated '(:good)))
          (should (eq seen-buf item-buf)))))))

(ert-deftest glasspane-srs-rate-binds-review-item ()
  "srs.rate binds `org-srs-review-item' to nil so the session-less real
`org-srs-review-rate' takes its explicit-args path instead of reading a
void variable (the on-device loop: rating errored, so the card never
rescheduled and kept reappearing)."
  (jetpacs-tests--with-fake-org-srs
    (with-temp-buffer
      (let ((item-buf (current-buffer))
            (seen 'unset))
        (cl-letf (((symbol-function 'org-srs-item-marker)
                   (lambda (&rest _)
                     (with-current-buffer item-buf (copy-marker (point-min)))))
                  ((symbol-function 'org-srs-review-rate)
                   (lambda (_rating &rest _)
                     (setq seen (if (boundp 'org-srs-review-item)
                                    org-srs-review-item 'void)))))
          (setq glasspane-srs--active t
                glasspane-srs--current (list '(card back) "a" item-buf)
                glasspane-srs--revealed t)
          (jetpacs--on-action
           '((action . "srs.rate") (args . ((rating . "good")))) nil)
          (should (eq seen nil)))))))

(ert-deftest glasspane-srs-item-create-at-ref ()
  "srs.item.create resolves the ref and runs org-srs-item-create with
the heading current (its prompts bridge to phone dialogs upstream)."
  (let ((file (make-temp-file "jetpacs-srs" nil ".org"))
        (created nil))
    (with-temp-file file (insert "* Alpha\nBody.\n* Beta\nMore.\n"))
    (unwind-protect
        (jetpacs-tests--with-fake-org-srs
          (cl-letf (((symbol-function 'org-srs-item-create)
                     (lambda ()
                       (setq created (org-get-heading t t t t)))))
            (jetpacs--on-action
             `((action . "srs.item.create")
               (args . ((file . ,file) (pos . 18)))) ; inside Beta
             nil)
            (should (equal created "Beta"))
            (should (string-search "created" (or jetpacs-shell--snackbar "")))))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

(ert-deftest glasspane-demo-srs-registration ()
  "Demo setup registers flashcards.org as review items when org-srs is
around: cards at the card headings, cloze targets wrapped in place,
one items-update per cloze entry.  Without org-srs the file is still
written as plain org."
  (let ((dir (make-temp-file "jetpacs-demo-srs" t))
        (created nil) (clozed nil) (updated 0))
    (unwind-protect
        (progn
          (let ((glasspane-srs--available t))
            (cl-letf (((symbol-function 'org-srs-item-new)
                       (lambda (_type)
                         (push (org-get-heading t t t t) created)))
                      ((symbol-function 'org-srs-item-cloze-default)
                       (lambda (start end &optional _hint)
                         (push (buffer-substring-no-properties start end)
                               clozed)))
                      ((symbol-function 'org-srs-item-cloze-update-entry)
                       (lambda (&optional _) (cl-incf updated))))
              (glasspane-demo-setup-org dir)))
          (should (equal (sort created #'string<)
                         '("Mass–energy equivalence"
                           "What does the Gaussian integral evaluate to?")))
          (should (equal (sort clozed #'string<) '("1947" "a moth")))
          (should (= updated 1))
          ;; Unavailable → written but unregistered, no error.
          (let ((glasspane-srs--available nil))
            (setq created nil)
            (glasspane-demo-setup-org dir)
            (should-not created)
            (should (file-exists-p (expand-file-name "flashcards.org" dir)))))
      (when-let ((buf (find-buffer-visiting
                       (expand-file-name "flashcards.org" dir))))
        (kill-buffer buf))
      (delete-directory dir t))))

(ert-deftest glasspane-srs-detail-section-and-hook-seam ()
  "The detail splice hook carries both layers: the SRS section appears
through `glasspane-ui-detail-nodes-functions', and an erroring
contributor costs only itself."
  (jetpacs-tests--with-fake-org-srs
    (cl-letf (((symbol-function 'glasspane-ui--detail-body)
               (lambda (_ref) (jetpacs-lazy-column (jetpacs-text "The body" 'body)))))
      (let* ((glasspane-ui-detail-nodes-functions
              (list (lambda (_ref) (error "broken contributor"))
                    #'glasspane-srs-detail-nodes))
             (json (json-serialize
                    (jetpacs-tests--canon
                     (glasspane-ui--detail-body-with-notes '((id . "x"))))
                    :null-object :null :false-object :false)))
        (should (string-search "The body" json))
        (should (string-search "Make flashcard" json))
        (should (string-search "srs.item.create" json))))))

(provide 'jetpacs-tests)
;;; jetpacs-tests.el ends here
