;;; glasspane-journal-test.el --- Tests for glasspane-journal
;;; Code:

(require 'glasspane-test-helpers)

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
          (jetpacs-org-cache-invalidate 'glasspane)
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
          (jetpacs-org-cache-invalidate 'glasspane)
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

(provide 'glasspane-journal-test)
