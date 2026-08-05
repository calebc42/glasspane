;;; jetpacs-transient-test.el --- ERT for the transient dialog bridge -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; The bridge is driven below the wire: `jetpacs-dialog--ask' is stubbed
;; to answer a conclusion directly, so these tests exercise layout
;; reading, field capture, argument reconstruction, and suffix dispatch
;; against a REAL `transient-define-prefix' (whatever layout shape the
;; running Emacs's bundled transient produces — that is the point).

(require 'ert)
(require 'jetpacs-transient)

(defvar jetpacs-transient-test--ran 'unset
  "What the suffix saw from `transient-args', or `unset'.")

(defun jetpacs-transient-test--suffix ()
  (interactive)
  (setq jetpacs-transient-test--ran
        (transient-args 'jetpacs-transient-test--prefix)))

(transient-define-prefix jetpacs-transient-test--prefix ()
  "A switch, an option, and one suffix."
  ["Arguments"
   ("-a" "All of them" "--all")
   ("-u" "Author" "--author=")]
  ["Actions"
   ("c" "Commit it" jetpacs-transient-test--suffix)])

(defun jetpacs-transient-test--walk (node fn)
  (funcall fn node)
  (mapc (lambda (c) (jetpacs-transient-test--walk c fn))
        (append (plist-get node :children) nil)))

(defmacro jetpacs-transient-test--showing (conclusion &rest body)
  "Run BODY with `jetpacs-dialog--ask' answering CONCLUSION.
Captured specs collect newest-first in `specs'; per-prefix argument
state and the suffix recorder reset around BODY."
  (declare (indent 1))
  `(let ((specs nil)
         (jetpacs-transient--values nil)
         (jetpacs-transient-test--ran 'unset))
     (ignore jetpacs-transient-test--ran)
     (cl-letf (((symbol-function 'jetpacs-dialog--ask)
                (lambda (spec) (push spec specs) ,conclusion)))
       ,@body)))

(ert-deftest jetpacs-transient-groups-parses-real-layout ()
  "The version-normalising readers parse the bundled transient's shape."
  (let ((groups (jetpacs-transient--groups 'jetpacs-transient-test--prefix)))
    (should (= 2 (length groups)))
    (pcase-let ((`((,d1 . ,args) (,d2 . ,acts)) groups))
      (should (equal d1 "Arguments"))
      (should (equal d2 "Actions"))
      (should (equal (mapcar (lambda (k) (plist-get k :argument)) args)
                     '("--all" "--author=")))
      (should (eq (plist-get (car acts) :command)
                  'jetpacs-transient-test--suffix)))))

(ert-deftest jetpacs-transient-submit-invokes-with-args ()
  "Captured fields become transient-args for the tapped suffix."
  (jetpacs-transient-test--showing
      '("submitted" (:value "jetpacs-transient-test--suffix"
                     :fields (:a0 t :a1 "Ada"))
        nil)
    (jetpacs-transient--show 'jetpacs-transient-test--prefix)
    (should (equal jetpacs-transient-test--ran '("--all" "--author=Ada")))
    ;; The state persists per prefix for the next opening.
    (should (equal (alist-get 'jetpacs-transient-test--prefix
                              jetpacs-transient--values)
                   '("--all" "--author=Ada")))))

(ert-deftest jetpacs-transient-reopen-shows-stored-state ()
  "A reopened prefix seeds its checkbox and option field from state."
  (jetpacs-transient-test--showing '("dismissed" nil nil)
    (setf (alist-get 'jetpacs-transient-test--prefix
                     jetpacs-transient--values)
          '("--all" "--author=Ada"))
    (jetpacs-transient--show 'jetpacs-transient-test--prefix)
    (let (checked option)
      (jetpacs-transient-test--walk
       (car specs)
       (lambda (n)
         (pcase (plist-get n :t)
           ("checkbox" (setq checked (plist-get n :checked)))
           ("text_input" (setq option (plist-get n :value))))))
      (should (eq checked t))
      (should (equal option "Ada")))))

(ert-deftest jetpacs-transient-unchecked-and-empty-drop-out ()
  "A :json-false checkbox and an empty option contribute no argument."
  (should (equal (jetpacs-transient--args-from-fields
                  '(:a0 :json-false :a1 "")
                  '(("a0" . "--all") ("a1" . "--author=")))
                 nil)))

(ert-deftest jetpacs-transient-dismissal-is-quiet ()
  "Closing the menu invokes nothing and signals nothing."
  (jetpacs-transient-test--showing '("dismissed" nil nil)
    (jetpacs-transient--show 'jetpacs-transient-test--prefix)
    (should (eq jetpacs-transient-test--ran 'unset))))

(provide 'jetpacs-transient-test)
;;; jetpacs-transient-test.el ends here