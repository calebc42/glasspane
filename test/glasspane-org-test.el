;;; glasspane-org-test.el --- Tests for glasspane-org
;;; Code:

(require 'glasspane-test-helpers)

(ert-deftest glasspane-org-surfaces-as-data ()
  "The capture tile, clock widget, and widget header button are pure data.
These replaced the companion's CaptureTileService /
JetpacsClockWidgetProvider / hardcoded header wiring (jetpacs 55b5a23) —
the specs must carry the org actions the Kotlin used to hardcode."
  ;; Clock widget: two silent queue-policy rows.
  (let* ((spec (glasspane-clock-widget-spec))
         (items (append (alist-get 'items spec) nil)))
    (should (= 2 (length items)))
    (should (equal "org.clock.in-last"
                   (alist-get 'action (alist-get 'on_tap (nth 0 items)))))
    (should (equal "org.clock.out"
                   (alist-get 'action (alist-get 'on_tap (nth 1 items)))))
    ;; Silent broadcasts: taps must not open the app.
    (should-not (assq 'tap_in_app (nth 0 items))))
  ;; Capture tile: an in-app tap carrying org.capture.show.
  (let ((glasspane-ui--capture-tile-pushed nil)
        pushed)
    (cl-letf (((symbol-function 'jetpacs-surface-push)
               (lambda (surface spec &rest _) (push (cons surface spec) pushed))))
      (glasspane-ui--push-capture-tile)
      (let ((tile (cdr (assoc "tile:custom1" pushed))))
        (should tile)
        (should (eq (alist-get 'tap_in_app tile) t))
        (should (equal "org.capture.show"
                       (alist-get 'action (alist-get 'on_tap tile)))))
      ;; Once per session: a second call pushes nothing new.
      (glasspane-ui--push-capture-tile)
      (should (= 1 (length pushed)))))
  ;; Agenda widget: header_action rides at the spec top level (SPEC §4,
  ;; a sibling of views — chrome is view-independent).
  (let ((glasspane-ui--last-widget 'unset)
        (glasspane-org-custom-agendas nil)
        pushed)
    (cl-letf (((symbol-function 'jetpacs-surface-push)
               (lambda (surface spec &rest _) (push (cons surface spec) pushed)))
              ((symbol-function 'glasspane-org--agenda-items)
               (lambda (&rest _) nil)))
      (glasspane-ui--push-widget)
      (let ((spec (cdr (assoc "widget:agenda" pushed))))
        (should spec)
        (should (assq 'views spec))
        (should (equal "org.capture.show"
                       (alist-get 'action (alist-get 'header_action spec))))))))

;; ─── Extraction cache ───────────────────────────────────────────────────────

(ert-deftest glasspane-org-cache-memoises ()
  "Readers memoise until `jetpacs-org-cache-invalidate' drops the namespace."
  (let ((n 0))
    (cl-letf (((symbol-function 'glasspane-org--todo-items-1)
               (lambda (_files) (setq n (1+ n)) '(fake))))
      (jetpacs-org-cache-invalidate 'glasspane)
      (glasspane-org--todo-items)
      (glasspane-org--todo-items)
      (should (= n 1))
      (jetpacs-org-cache-invalidate 'glasspane)
      (glasspane-org--todo-items)
      (should (= n 2)))))

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

(ert-deftest glasspane-org-reader-heading-overflow-menu ()
  "Every reader heading header carries the quick-action overflow menu;
the clocked-in heading offers Clock Out instead of Clock In."
  (let ((file (make-temp-file "jetpacs-menu-test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "* Alpha\n* Beta\n"))
          (let* ((nodes (glasspane-org-reader-file file))
                 (json (json-serialize
                        (jetpacs-tests--canon (apply #'jetpacs-column nodes))
                        :null-object :null :false-object :false)))
            (should (jetpacs-tests--find-node
                     nodes (lambda (n) (equal (alist-get 't n) "menu"))))
            (should (string-search "Clock In" json))
            (should-not (string-search "Clock Out" json))
            (should (string-search "heading.planning.show" json))
            (should (string-search "SCHEDULED" json))
            (should (string-search "DEADLINE" json))
            (should (string-search "heading.priority" json))
            (should (string-search "heading.tags" json))
            (should (string-search "heading.props.show" json))
            (should (string-search "heading.duplicate" json))
            (should (string-search "\"ask\":true" json))))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

(ert-deftest glasspane-org-priority-string-normalizes ()
  "Vulpea hands back org-element's raw :priority (the char code, or its
decimal string via SQLite); the items must carry the letter."
  (should (equal (glasspane-org--priority-string ?A) "A"))
  (should (equal (glasspane-org--priority-string 66) "B"))
  (should (equal (glasspane-org--priority-string "67") "C"))
  (should (equal (glasspane-org--priority-string "A") "A"))
  (should-not (glasspane-org--priority-string nil)))

(ert-deftest glasspane-org-reader-pretty-headers ()
  "Reader headers render structured: colored todo/priority spans, a
struck-through done title, and tag chips — not the raw org line."
  (let ((file (make-temp-file "jetpacs-pretty-test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* TODO [#A] Fix the backup job :urgent:infra:\n"
                    "* DONE Migrate the sync\n"))
          (let ((json (json-serialize
                       (jetpacs-tests--canon
                        (apply #'jetpacs-column (glasspane-org-reader-file file)))
                       :null-object :null :false-object :false)))
            ;; Tags are chips, not ":urgent:infra:" text.
            (should-not (string-search ":urgent:infra:" json))
            (should (string-search "search.by-tag" json))
            (should (string-search "\"urgent\"" json))
            (should (string-search "[#A] " json))
            (should (string-search "Fix the backup job" json))
            ;; The done heading strikes through.
            (should (string-search "\"strike\":true" json))))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

(ert-deftest glasspane-org-reader-header-badges ()
  "Reader headers carry deadline and clocked badges under their toggles:
deadline in orange (red+bold once overdue), clock totals as h:mm."
  (let ((file (make-temp-file "jetpacs-badges-test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* TODO Pay the bill\nDEADLINE: <2001-01-05 Fri>\n"
                    "* Logged work\n:LOGBOOK:\n"
                    "CLOCK: [2026-07-03 Fri 10:00]--[2026-07-03 Fri 11:30] =>  1:30\n"
                    ":END:\n"))
          (let ((json (json-serialize
                       (jetpacs-tests--canon
                        (apply #'jetpacs-column (glasspane-org-reader-file file)))
                       :null-object :null :false-object :false)))
            (should (string-search "Deadline 2001-01-05" json))
            (should (string-search glasspane-org-reader--overdue-color json))
            ;; Clock badge is opt-in and off by default.
            (should-not (string-search "clocked" json)))
          (let* ((glasspane-org-reader-show-clocked t)
                 (json (json-serialize
                        (jetpacs-tests--canon
                         (apply #'jetpacs-column (glasspane-org-reader-file file)))
                        :null-object :null :false-object :false)))
            (should (string-search "1:30 clocked" json)))
          (let* ((glasspane-org-reader-show-deadline nil)
                 (json (json-serialize
                        (jetpacs-tests--canon
                         (apply #'jetpacs-column (glasspane-org-reader-file file)))
                        :null-object :null :false-object :false)))
            (should-not (string-search "Deadline 2001-01-05" json))))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

(ert-deftest glasspane-org-reader-inline-props-switch ()
  "Binding `glasspane-org-reader-inline-props' off (the detail view)
drops the inline PROPERTIES drawers from reader output."
  (let ((file (make-temp-file "jetpacs-props-test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Top\n** Child\n:PROPERTIES:\n:KIND: demo\n:END:\n"))
          (let ((props-p (lambda (n)
                           (and (equal (alist-get 't n) "collapsible")
                                (equal (alist-get 'text (alist-get 'header n))
                                       "PROPERTIES")))))
            (should (jetpacs-tests--find-node
                     (glasspane-org-reader-subtree file 1 t) props-p))
            (let ((glasspane-org-reader-inline-props nil))
              (should-not (jetpacs-tests--find-node
                           (glasspane-org-reader-subtree file 1 t) props-p)))))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
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

(ert-deftest glasspane-org-toolbar-lints-and-roundtrips ()
  "The org toolbar is wire-valid data on an editor node (SPEC §9).
This list is the toolbar's specification of record — the companion's
OrgEditToolbar.kt is gone — so every op must stay inside the closed
vocabulary `jetpacs-lint' checks."
  (let ((ed (jetpacs-editor "f.org" "content"
                         :syntax "org"
                         :toolbar (glasspane-org-toolbar))))
    (should-not (jetpacs-lint-spec ed))
    (let* ((toolbar (alist-get 'toolbar (jetpacs-render-to-json ed)))
           (items (append toolbar nil)))
      (should (vectorp toolbar))
      (should (= 18 (length items)))
      ;; The long-press secondaries (progress cookie, timestamp) survive.
      (should (= 2 (cl-count-if (lambda (item) (assq 'long_press item)) items)))
      ;; The src menu keeps its free-form ${input:Language} escape.
      (should (cl-find-if
               (lambda (item)
                 (cl-find-if (lambda (sub)
                               (string-search "${input:Language}"
                                              (or (alist-get 'snippet sub) "")))
                             (append (alist-get 'menu item) nil)))
               items)))))

;; ─── Query routing (vulpea index vs org-ql) ─────────────────────────────────

(ert-deftest glasspane-org-query-routes-supported-to-index ()
  "An index-evaluable tree answers off the vulpea note index."
  (cl-letf (((symbol-function 'glasspane-org--vulpea-p) (lambda () t))
            ((symbol-function 'glasspane-org--vulpea-query)
             (lambda (tree) (list `((routed . index) (tree . ,tree))))))
    (jetpacs-org-cache-invalidate 'glasspane)
    (let ((items (glasspane-org--query '(todo "TODO"))))
      (should (equal (alist-get 'routed (car items)) 'index)))))

(ert-deftest glasspane-org-query-routes-unsupported-to-org-ql ()
  "A tree outside `jetpacs-org-note-query-terms' bypasses the index and
runs through `jetpacs-org-query' (org-ql / built-in, agenda scope) —
the 1.6.0 routing rule, instead of the old user-error."
  (let (called)
    (cl-letf (((symbol-function 'glasspane-org--vulpea-p) (lambda () t))
              ((symbol-function 'glasspane-org--vulpea-query)
               (lambda (_tree) (error "index arm must not run")))
              ((symbol-function 'jetpacs-org-query)
               (lambda (_ns tree _action) (setq called tree) nil)))
      (glasspane-org--query '(ts :from -7))
      (should (equal called '(ts :from -7))))))

(provide 'glasspane-org-test)
