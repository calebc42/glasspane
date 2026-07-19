;;; glasspane-ui-test.el --- Tests for glasspane-ui
;;; Code:

(require 'glasspane-test-helpers)

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

(ert-deftest glasspane-ui-absorbs-core-files-and-eval-tabs ()
  "Loading Glasspane suppresses the core's vanilla \"Jetpacs\" app,
so the stock Files and Eval tabs ride Glasspane's own bottom bar and
the unowned core drawer entries (Buffers, Messages, Tools) switch to
views that are actually in the push — not dead taps in a second app."
  ;; Single-app mode: Glasspane is the only registered app.
  (should (equal (mapcar #'car jetpacs-apps--registry) '("glasspane")))
  ;; Every stock view passes the app filter again...
  (dolist (v '("files" "eval" "buffers" "messages" "tools"))
    (should (jetpacs-shell--view-filtered-p v)))
  ;; ...and the bar reads org tabs first, then the stock pair.
  (should (equal (cl-remove-if-not #'jetpacs-shell--tab-p
                                   (mapcar #'car jetpacs-shell-views))
                 '("glasspane.agenda" "glasspane.journal" "glasspane.tasks"
                   "files" "eval"))))

;; ─── Heading mutations: add/delete/copy-link and prompted set-ops ───────────

(defmacro glasspane-ui-test--with-org-file (content &rest body)
  "Run BODY with `file' bound to a temp org FILE holding CONTENT.
`jetpacs-shell-push' is stubbed out; the buffer and file are cleaned up."
  (declare (indent 1))
  `(let ((file (make-temp-file "jetpacs-ui-test" nil ".org")))
     (with-temp-file file (insert ,content))
     (unwind-protect
         (cl-letf (((symbol-function 'jetpacs-shell-push)
                    (cl-function (lambda (&optional _tab &key _switch-to)))))
           ,@body)
       (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
       (delete-file file))))

(defun glasspane-ui-test--file-content (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(ert-deftest glasspane-ui-add-heading-child-and-sibling ()
  "heading.add-heading nests a child at the end of the subtree;
heading.add-sibling lands at the same level after it."
  (glasspane-ui-test--with-org-file "* Parent\nBody.\n** Child\n"
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "Fresh")))
      (jetpacs--on-action
       `((action . "heading.add-heading")
         (args . ((file . ,file) (pos . 1) (headline . "Parent"))))
       nil))
    (should (string-search "** Child\n** Fresh\n"
                           (glasspane-ui-test--file-content file)))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "Next")))
      (jetpacs--on-action
       `((action . "heading.add-sibling")
         (args . ((file . ,file) (pos . 1) (headline . "Parent"))))
       nil))
    (should (string-search "** Fresh\n* Next\n"
                           (glasspane-ui-test--file-content file)))))

(ert-deftest glasspane-ui-delete-heading-removes-subtree ()
  "heading.delete confirms, then removes the whole subtree — no archive."
  (glasspane-ui-test--with-org-file "* Keep\n* Kill\n** Sub\nBody.\n* After\n"
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
      (jetpacs--on-action
       `((action . "heading.delete")
         (args . ((file . ,file) (pos . 8) (headline . "Kill"))))
       nil))
    (let ((content (glasspane-ui-test--file-content file)))
      (should (equal content "* Keep\n* After\n"))))
  ;; Declining the confirm leaves the file untouched.
  (glasspane-ui-test--with-org-file "* Kill\n"
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
      (jetpacs--on-action
       `((action . "heading.delete")
         (args . ((file . ,file) (pos . 1) (headline . "Kill"))))
       nil))
    (should (equal (glasspane-ui-test--file-content file) "* Kill\n"))))

(ert-deftest glasspane-ui-file-add-heading-appends-top-level ()
  "file.add-heading appends a top-level heading at the end of the file."
  (glasspane-ui-test--with-org-file "* One\n** Two\n"
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "Tail")))
      (jetpacs--on-action
       `((action . "file.add-heading") (args . ((file . ,file))))
       nil))
    (should (equal (glasspane-ui-test--file-content file)
                   "* One\n** Two\n* Tail\n"))))

(ert-deftest glasspane-ui-copy-link-item-id-and-file-links ()
  "The Copy Link chip carries an id link when the heading has an :ID:,
a file::*headline link otherwise — dispatched companion-locally."
  (glasspane-ui-test--with-org-file
      "* Plain\n* Known\n:PROPERTIES:\n:ID: known-42\n:END:\n"
    (let* ((item (glasspane-ui--detail-copy-link-item
                  `((file . ,file) (pos . 9) (headline . "Known"))))
           (json (json-serialize (jetpacs-tests--canon item)
                                 :null-object :null :false-object :false)))
      (should (string-search "clipboard.copy" json))
      (should (string-search "[[id:known-42][Known]]" json)))
    (let* ((item (glasspane-ui--detail-copy-link-item
                  `((file . ,file) (pos . 1) (headline . "Plain"))))
           (json (json-serialize (jetpacs-tests--canon item)
                                 :null-object :null :false-object :false)))
      (should (string-search "clipboard.copy" json))
      (should (string-search "::*Plain" json)))))

(ert-deftest glasspane-ui-schedule-and-priority-prompt-paths ()
  "With no value on the wire, heading.schedule asks through org-read-date
and heading.priority (ask) through a bridged read-string."
  (glasspane-ui-test--with-org-file "* Task\n"
    (cl-letf (((symbol-function 'org-read-date)
               (lambda (&rest _) "2026-08-01")))
      (jetpacs--on-action
       `((action . "heading.schedule")
         (args . ((file . ,file) (pos . 1) (headline . "Task"))))
       nil))
    (should (string-search "SCHEDULED: <2026-08-01"
                           (glasspane-ui-test--file-content file)))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "b")))
      (jetpacs--on-action
       `((action . "heading.priority")
         (args . ((ask . t) (file . ,file) (pos . 1) (headline . "Task"))))
       nil))
    (should (string-search "* [#B] Task"
                           (glasspane-ui-test--file-content file)))))

(provide 'glasspane-ui-test)
