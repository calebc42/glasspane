;;; jetpacs-org-settings-test.el --- ERT for the relocated org sections -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; The §3 relocation's gate (docs/PLAN-jetpacs-debt-and-scaffold): the
;; org/calendar schema sections register at the module's LOAD (not
;; behind an app gate) and the foundation after-set drops the WHOLE
;; org memo.

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

(provide 'jetpacs-org-settings-test)
;;; jetpacs-org-settings-test.el ends here
