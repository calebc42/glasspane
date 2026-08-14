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

;;;; The org-workflow editors (§3 step 2)

(ert-deftest jetpacs-org-settings-todo-helpers ()
  "The pure TODO-keyword helpers: the explicit-bar split, org's
last-keyword-is-finished rule for bar-less sequences, the fast-access
strip in the flat global list, and the comma parse."
  (should (equal (jetpacs-org-settings--split-todo-sequence
                  '(sequence "TODO(t!)" "NEXT" "|" "DONE(d)"))
                 (cons '("TODO(t!)" "NEXT") '("DONE(d)"))))
  (should (equal (jetpacs-org-settings--split-todo-sequence
                  '(sequence "TODO" "DONE"))
                 (cons '("TODO") '("DONE"))))
  (should (equal (jetpacs-org-settings--split-todo-sequence
                  '(sequence "DONE"))
                 (cons nil '("DONE"))))
  (should (equal (jetpacs-org-settings--split-todo-sequence
                  '(sequence "TODO" "|"))
                 (cons '("TODO") nil)))
  (let ((org-todo-keywords '((sequence "TODO(t)" "|" "DONE(d!)")
                             (type "BUG(b)" "FIXED"))))
    (should (equal (jetpacs-org-settings-global-todo-keywords)
                   '("TODO" "DONE" "BUG" "FIXED"))))
  (should (equal (jetpacs-org-settings--parse-keywords " TODO , , DOING ")
                 '("TODO" "DOING")))
  (should-not (jetpacs-org-settings--parse-keywords "  ,  "))
  (should-not (jetpacs-org-settings--parse-keywords 42)))

(ert-deftest jetpacs-org-settings-tag-options-and-enum ()
  "Tag options survive group markers and duplicates (the enum's
build-time distinctness check); the chip list builds and serializes."
  (let ((org-tag-alist '(("home" . ?h) (:startgroup) "work" "home")))
    (should (equal (jetpacs-org-settings-tag-options) '("home" "work")))
    (let ((json (jetpacs-node->canonical-json
                 (jetpacs-org-settings--tags-enum))))
      (should (string-search "\"org-tags\"" json))
      (should (string-search "jetpacs.org.tags" json))
      (should (string-search "\"allow_add\":true" json)))))

(ert-deftest jetpacs-org-settings-workflow-verbs ()
  "The whole family registered OWNERLESS at load — present in the
handler table, absent from the any-surface set (ownerless is
gate-exempt; the app-era `:any-surface' dance has no successor) — and
the workflow body/link/screen round-trip the canonical encoding."
  (dolist (name '("jetpacs.org.workflow.open" "jetpacs.org.tags"
                  "jetpacs.org.todo.edit" "jetpacs.org.todo.save"
                  "jetpacs.org.todo.delete"))
    (should (gethash name jetpacs-action-handlers))
    (should-not (gethash name jetpacs--any-surface-actions))
    (should-not (jetpacs--owner-of "action" name)))
  (should (cl-find #'jetpacs-org-settings--link jetpacs-settings-links
                   :key #'cadr))
  (let ((org-todo-keywords '((sequence "TODO(t)" "|" "DONE")))
        (org-tag-alist '("home")))
    (let* ((body (jetpacs-org-settings--workflow-body))
           (json (jetpacs-node->canonical-json body)))
      (should (equal (plist-get body :t) "lazy_column"))
      (should (string-search "Sequence 1" json))
      (should (string-search "TODO | DONE" json))
      (should (string-search "jetpacs.org.todo.edit" json)))
    (let ((screen (jetpacs-org-settings--workflow-screen nil)))
      (should (equal (plist-get screen :t) "scaffold")))
    (should (string-search "jetpacs.org.workflow.open"
                           (jetpacs-node->canonical-json
                            (jetpacs-org-settings--link))))))

(ert-deftest jetpacs-org-settings-editor-handlers ()
  "The moved handler arms, driven straight from the handler table:
tags vector rebuilds keeping fast-select conses / empty vector is a
no-op / junk rejects; todo.edit coerces org.json's whole floats and
answers stale for vanished indices, rejected with no client;
todo.save writes through `jetpacs-settings-save-variable' with the
captured fields, stale on a raced index, rejected on empty states;
todo.delete falls back to the stock sequence on last-delete."
  (let ((org-tag-alist '(("home" . ?h)))
        (org-todo-keywords '((sequence "TODO" "|" "DONE")))
        (jetpacs-settings--dialog nil)
        (saved nil) (continuations nil))
    (cl-letf (((symbol-function 'jetpacs-settings-save-variable)
               (lambda (sym val)
                 (push (cons sym val) saved) (set sym val) val))
              ((symbol-function 'jetpacs-shell-notify)
               (lambda (&rest _) nil))
              ((symbol-function 'jetpacs-toast) (lambda (&rest _) nil))
              ((symbol-function 'jetpacs-shell-push) (lambda (&rest _) nil))
              ((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (push fn continuations) nil)))
      (cl-flet ((run (name args &optional params)
                  (funcall (gethash name jetpacs-action-handlers)
                           args params)))
        ;; jetpacs.org.tags
        (should (eq (run "jetpacs.org.tags" '(:value ["work" "home"]))
                    'accepted))
        (should (equal org-tag-alist '("work" ("home" . ?h))))
        (should (assq 'org-tag-alist saved))
        (setq saved (assq-delete-all 'org-tag-alist saved))
        (should (eq (run "jetpacs.org.tags" '(:value [])) 'accepted))
        (should-not (assq 'org-tag-alist saved))
        (should (eq (run "jetpacs.org.tags" '(:value 42)) 'rejected))
        (should (eq (run "jetpacs.org.tags" '(:value ["x" 5])) 'rejected))
        ;; jetpacs.org.todo.edit
        (should (eq (run "jetpacs.org.todo.edit" '(:index 99)) 'stale))
        (should (eq (run "jetpacs.org.todo.edit" '(:index "x")) 'rejected))
        (should (eq (run "jetpacs.org.todo.edit" '(:index 0)) 'rejected))
        (should (eq (run "jetpacs.org.todo.edit" '(:index -1.0)) 'rejected))
        ;; jetpacs.org.todo.save
        (should (eq (run "jetpacs.org.todo.save"
                         '(:index 0 :type "sequence")
                         '(:fields (:todo-active "TODO, DOING"
                                    :todo-finished "DONE")))
                    'accepted))
        (should (equal (cdr (assq 'org-todo-keywords saved))
                       '((sequence "TODO" "DOING" "|" "DONE"))))
        (should (eq (run "jetpacs.org.todo.save"
                         '(:index 99 :type "sequence")
                         '(:fields (:todo-active "TODO")))
                    'stale))
        (should (eq (run "jetpacs.org.todo.save"
                         '(:index 0 :type "sequence")
                         '(:fields (:todo-active " , " :todo-finished "")))
                    'rejected))
        (should (eq (run "jetpacs.org.todo.save"
                         '(:index "x" :type "sequence")
                         '(:fields (:todo-active "TODO")))
                    'rejected))
        (should (eq (run "jetpacs.org.todo.save"
                         '(:index -1 :type "type")
                         '(:fields (:todo-active "BUG, FEATURE")))
                    'accepted))
        (should (= (length (default-value 'org-todo-keywords)) 2))
        (should (equal (nth 1 (default-value 'org-todo-keywords))
                       '(type "BUG" "FEATURE")))
        ;; jetpacs.org.todo.delete
        (should (eq (run "jetpacs.org.todo.delete" '(:index 9)) 'stale))
        (should (eq (run "jetpacs.org.todo.delete" '(:index 1)) 'accepted))
        (should (eq (run "jetpacs.org.todo.delete" '(:index 0)) 'accepted))
        (should (equal (default-value 'org-todo-keywords)
                       '((sequence "TODO" "|" "DONE"))))))))

(provide 'jetpacs-org-settings-test)
;;; jetpacs-org-settings-test.el ends here
