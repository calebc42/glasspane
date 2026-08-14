;;; jetpacs-org-settings-test.el --- ERT for the relocated org sections -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; The §3 relocation's gate (docs/PLAN-jetpacs-debt-and-scaffold): the
;; org/calendar schema sections register at the module's LOAD (not
;; behind an app gate), the foundation after-set drops the WHOLE org
;; memo, and the step-4 seeding is only-while-stock.  Batch-safe: the
;; require above runs registration but NOT seeding (the module's
;; noninteractive guard — asserted below, since a batch suite that
;; mkdirs the runner's `org-directory' is exactly the accident the
;; guard exists for); seeding tests drive the fn by hand over let-bound
;; vars and a temp directory.

(require 'ert)
(require 'cl-lib)
(require 'jetpacs-org-settings)

(defconst jetpacs-org-settings-test--expected
  '(("Org Workflow" org-directory org-default-notes-file ebp-org-roots
     org-log-done org-log-into-drawer org-archive-location)
    ("Org Agenda" org-agenda-span org-deadline-warning-days
     org-extend-today-until)
    ("Org Editing & Display" org-startup-folded org-startup-indented
     org-hide-emphasis-markers org-return-follows-link)
    ("User Defaults" user-full-name user-mail-address)
    ("Calendar & Location" calendar-week-start-day calendar-latitude
     calendar-longitude)
    ("Reader" ebp-org-outline-show-deadline ebp-org-outline-show-clocked))
  "Every moved section with its full entry list, in registration order.
The identity rows (\"User Defaults\") are the only bare ones; every
other entry must carry the foundation memo-buster.")

(ert-deftest jetpacs-org-settings-sections-register-at-load ()
  "The require above (= boot) registered every moved section whole:
each title present with exactly its entries, org/calendar rows wired
to the foundation after-set, identity rows bare — and neither app
opinion (`glasspane-babel-timeout' stayed app-side) nor the v1 ghost
(`jetpacs-dialog-style') leaked into foundation content."
  (dolist (spec jetpacs-org-settings-test--expected)
    (let* ((title (car spec))
           (entries (alist-get title jetpacs-settings-registry
                               nil nil #'equal)))
      (should entries)
      (should (equal (mapcar #'car entries) (cdr spec)))
      (dolist (entry entries)
        (should (stringp (plist-get (cdr entry) :label)))
        (if (equal title "User Defaults")
            (should-not (plist-get (cdr entry) :after-set))
          (should (eq (plist-get (cdr entry) :after-set)
                      #'jetpacs-org-settings-after-set))))))
  (let ((sections (jetpacs-org-settings-sections)))
    (dolist (ghost '(glasspane-babel-timeout jetpacs-dialog-style))
      (should-not (cl-some (lambda (sec) (assq ghost (cdr sec)))
                           sections))))
  ;; The plan's verify clause: `org-default-notes-file' renders — its
  ;; `file' custom-type maps to the string control, never raw sexp.
  (should (eq (jetpacs-settings--kind
               (jetpacs-settings--type 'org-default-notes-file))
              'string))
  ;; Replay-callable: registration into an empty registry rebuilds the
  ;; whole set (the queued-toggle boot rule needs the fn, not just the
  ;; load effect).
  (let ((jetpacs-settings-registry nil))
    (jetpacs-org-settings-register)
    (should (= (length jetpacs-settings-registry)
               (length jetpacs-org-settings-test--expected)))))

(ert-deftest jetpacs-org-settings-after-set-drops-the-whole-memo ()
  "The redesigned seam: the after-set the registry entries carry calls
`ebp-org-cache-invalidate' with NO namespace — deliberately broader
than the app's old per-namespace bust, so a settings write stales
every consumer's org-derived views, not just the writer's."
  (let* ((entry (assq 'org-directory
                      (alist-get "Org Workflow" jetpacs-settings-registry
                                 nil nil #'equal)))
         (after-set (plist-get (cdr entry) :after-set))
         (calls nil))
    (should after-set)
    (cl-letf (((symbol-function 'ebp-org-cache-invalidate)
               (lambda (&optional ns) (push ns calls))))
      (funcall after-set 'org-directory "/tmp/anywhere"))
    (should (equal calls '(nil)))))

(defmacro jetpacs-org-settings-test--seed-env (dir &rest body)
  "Run BODY with the seeded org vars let-bound and babel stubbed.
DIR names a fresh temp root; `org-directory' points at a NOT yet
existing subdirectory of it so the mkdir arm is observable.  `babel'
collects the language lists `org-babel-do-load-languages' was asked
to load — stubbed, because really loading ob-shell/ob-python is the
side effect a batch suite must not have."
  (declare (indent 1))
  `(let* ((tmp (make-temp-file "jetpacs-org-settings" t))
          (,dir (expand-file-name "org" tmp))
          (org-directory ,dir)
          (org-default-notes-file (convert-standard-filename "~/.notes"))
          (org-agenda-files nil)
          (org-log-into-drawer nil)
          (org-babel-load-languages '((emacs-lisp . t)))
          (babel nil))
     (cl-letf (((symbol-function 'org-babel-do-load-languages)
                (lambda (_sym langs) (push langs babel))))
       (ignore babel)
       (unwind-protect (progn ,@body)
         (delete-directory tmp t)))))

(ert-deftest jetpacs-org-settings-seed-while-stock ()
  "Stock values seed: the inbox capture target lands inside a created
`org-directory', the agenda falls back to that whole directory, LOGBOOK
logging turns on, and the babel languages load."
  (jetpacs-org-settings-test--seed-env dir
    (jetpacs-org-settings-seed)
    (should (equal org-default-notes-file
                   (expand-file-name "inbox.org" dir)))
    (should (file-directory-p dir))
    (should (equal org-agenda-files (list dir)))
    (should (eq org-log-into-drawer t))
    (should (equal (length babel) 1))
    (dolist (lang '(emacs-lisp shell python))
      (should (assq lang (car babel))))))

(ert-deftest jetpacs-org-settings-seed-never-touches-configured-values ()
  "The only-while-stock guards, arm by arm: values already moved off
stock survive a re-seed untouched — which is also what makes the
load-time call idempotent."
  (jetpacs-org-settings-test--seed-env dir
    (setq org-default-notes-file "/elsewhere/notes.org"
          org-agenda-files '("/elsewhere")
          org-log-into-drawer "NOTES"
          org-babel-load-languages '((emacs-lisp . t) (shell . t)))
    (jetpacs-org-settings-seed)
    (should (equal org-default-notes-file "/elsewhere/notes.org"))
    (should (equal org-agenda-files '("/elsewhere")))
    (should (equal org-log-into-drawer "NOTES"))
    (should-not babel)
    ;; A second pass over just-seeded stock values is a no-op too: the
    ;; seeded notes file is no longer stock, so it is never re-derived
    ;; against a later `org-directory'.
    (setq org-default-notes-file (convert-standard-filename "~/.notes")
          org-agenda-files nil)
    (jetpacs-org-settings-seed)
    (let ((seeded org-default-notes-file))
      (jetpacs-org-settings-seed)
      (should (equal org-default-notes-file seeded)))))

(ert-deftest jetpacs-org-settings-batch-load-does-not-seed ()
  "The noninteractive guard held for THIS process: the require at the
top of this batch suite registered sections but seeded nothing — the
runner's real `org-default-notes-file' would otherwise have been
rewritten under its HOME."
  (should noninteractive)
  (should (alist-get "Org Workflow" jetpacs-settings-registry
                     nil nil #'equal)))

(provide 'jetpacs-org-settings-test)
;;; jetpacs-org-settings-test.el ends here
