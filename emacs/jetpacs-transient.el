;;; jetpacs-transient.el --- Transient prefixes as touch dialogs -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; Transient prefixes (built into Emacs since 28; a growing share of
;; commands) are declarative specs: groups, keys, descriptions, switches
;; and options live in the `transient--layout' symbol property.  In a
;; device flow the keyboard popup would hang waiting for key events, so
;; an advice on `transient-setup' renders the prefix as ONE dialog
;; instead: switches become checkboxes, options become text fields, and
;; every suffix is a submit button that captures all of them — the
;; POC 1 bridge's custom toggle/invoke wire events collapse into
;; dialog-as-request field capture (SPEC 18.1).
;;
;; At invoke time `transient-args' is rebound so the suffix sees the
;; captured fields exactly as it would see transient's own state.  A
;; suffix that is itself a prefix re-enters the same advice, so nesting
;; works for free.  Argument state persists per prefix across openings.
;;
;; (Behavior reference: POC 1's jetpacs-transient.el.  The layout
;; readers are ported intact — the `transient--layout' shape changed
;; across transient versions and the two shapes are NOT compatible;
;; those readers were the hard-won part.)

;;; Code:

(require 'cl-lib)
(require 'transient)
(require 'jetpacs-widgets)
(require 'jetpacs-dialog)

(defvar jetpacs-transient--values nil
  "Alist of PREFIX -> list of active argument strings (\"--all\").")

;;;; Reading the layout (ported from POC 1, both transient shapes)

(defun jetpacs-transient--desc (plist fallback)
  "Resolve PLIST's :description (string or function) or FALLBACK."
  (let ((d (plist-get plist :description)))
    (cond ((stringp d) d)
          ((functionp d)
           (or (ignore-errors
                 (let ((s (funcall d)))
                   (and (stringp s) (substring-no-properties s))))
               fallback))
          (t fallback))))

(defun jetpacs-transient--visible-p (plist)
  "Evaluate PLIST's :if-style predicates; include the child on error."
  (cl-flet ((safe (f) (ignore-errors (funcall f))))
    (cond ((plist-member plist :if)
           (safe (plist-get plist :if)))
          ((plist-member plist :if-not)
           (not (safe (plist-get plist :if-not))))
          ((plist-member plist :if-non-nil)
           (symbol-value (plist-get plist :if-non-nil)))
          ((plist-member plist :if-nil)
           (not (symbol-value (plist-get plist :if-nil))))
          ((plist-member plist :if-mode)
           (derived-mode-p (plist-get plist :if-mode)))
          ((plist-member plist :if-not-mode)
           (not (derived-mode-p (plist-get plist :if-not-mode))))
          (t t))))

;; 0.7.x (Emacs 30 bundled): `transient--layout' is a LIST of group
;; vectors [LEVEL CLASS PLIST CHILDREN]; a leaf is (LEVEL CLASS (:k v)).
;; Newer: a single ROOT vector, groups [CLASS PLIST CHILDREN], leaves
;; inline as (transient-CLASS :k v …).  The readers normalise both.

(defun jetpacs-transient--vec-plist (g)
  "The property plist of a group vector G (nil or a keyword-keyed list)."
  (let ((n (length g)))
    (when (> n 1)
      (let ((cand (aref g (- n 2))))
        (and (consp cand) (keywordp (car cand)) cand)))))

(defun jetpacs-transient--vec-children (g)
  "The child-node list of a group vector G (its last slot when a list)."
  (let ((n (length g)))
    (when (> n 0)
      (let ((last (aref g (1- n))))
        (and (listp last) last)))))

(defun jetpacs-transient--leaf-plist (c)
  "The property plist of a suffix/infix leaf node C, across versions."
  (and (consp c)
       (cond
        ((keywordp (car c)) c)
        ((and (car c) (symbolp (car c))
              (string-prefix-p "transient-" (symbol-name (car c))))
         (cdr c))
        ((integerp (car c))
         (let ((rest (cddr c)))
           (cond ((keywordp (car-safe rest)) rest)
                 ((and (consp (car-safe rest))
                       (keywordp (car-safe (car rest))))
                  (car rest))
                 (t nil))))
        (t nil))))

(defun jetpacs-transient--groups (prefix)
  "Flatten PREFIX's layout into (DESCRIPTION . CHILDREN) groups.
Each child is a plist with :kind (`infix' or `suffix'), :description,
:argument and :command.  Robust to both layout shapes; visibility
predicates honoured where recognisable."
  (let (groups)
    (cl-labels
        ((walk-group (g inherited-desc)
           (when (vectorp g)
             (let* ((plist (jetpacs-transient--vec-plist g))
                    (children (jetpacs-transient--vec-children g))
                    (desc (jetpacs-transient--desc plist inherited-desc)))
               (when (jetpacs-transient--visible-p plist)
                 (if (cl-some #'vectorp children)
                     (dolist (sub children)
                       (when (vectorp sub) (walk-group sub desc)))
                   (let ((kids (delq nil (mapcar #'parse-child children))))
                     (when kids
                       (push (cons desc kids) groups))))))))
         (parse-child (c)
           (let ((plist (jetpacs-transient--leaf-plist c)))
             (when plist
               (let ((arg (plist-get plist :argument))
                     (cmd (plist-get plist :command)))
                 (when (jetpacs-transient--visible-p plist)
                   (cond
                    ((stringp arg)
                     (list :kind 'infix
                           :argument arg
                           :description (jetpacs-transient--desc plist arg)))
                    ((commandp cmd)
                     (list :kind 'suffix
                           :command cmd
                           :description
                           (jetpacs-transient--desc
                            plist
                            (capitalize
                             (replace-regexp-in-string
                              "-" " " (symbol-name cmd)))))))))))))
      (let ((layout (get prefix 'transient--layout)))
        (cond
         ((vectorp layout) (walk-group layout nil))
         ((listp layout) (dolist (g layout) (walk-group g nil))))))
    (nreverse groups)))

;;;; Rendering and dispatch (dialog-as-request)

(defun jetpacs-transient--arg-active (prefix arg)
  "The active stored value for ARG in PREFIX's state, or nil.
For options (\"--author=\") any stored value with that prefix counts."
  (let ((values (alist-get prefix jetpacs-transient--values)))
    (if (string-suffix-p "=" arg)
        (cl-find arg values :test #'string-prefix-p)
      (car (member arg values)))))

(defun jetpacs-transient--infix-nodes (prefix infixes)
  "Field nodes for INFIXES, returned as (NODES . (ID . ARGUMENT) alist).
Ids are positional (\"a0\"…) — argument strings like \"--all\" are not
node-id material."
  (let ((i -1) nodes ids)
    (dolist (k infixes)
      (let* ((arg (plist-get k :argument))
             (id (format "a%d" (cl-incf i)))
             (active (jetpacs-transient--arg-active prefix arg)))
        (push (cons id arg) ids)
        (push
         (if (string-suffix-p "=" arg)
             (jetpacs-text-input
              id :label (plist-get k :description) :single-line t
              :value (and active (substring active (length arg))))
           (jetpacs-checkbox
            id :checked (and active t)
            :label (plist-get k :description)))
         nodes)))
    (cons (nreverse nodes) (nreverse ids))))

(defun jetpacs-transient--args-from-fields (fields ids)
  "The transient argument strings FIELDS' captured values encode.
IDS is the (ID . ARGUMENT) alist the dialog was built with."
  (let (args)
    (pcase-dolist (`(,id . ,arg) ids)
      (let ((v (plist-get fields (intern (concat ":" id)))))
        (cond
         ((string-suffix-p "=" arg)
          (when (and (stringp v) (not (string-empty-p v)))
            (push (concat arg v) args)))
         ((eq v t) (push arg args)))))
    (nreverse args)))

(defun jetpacs-transient--show (prefix)
  "Render PREFIX as one dialog; invoke the tapped suffix with its args."
  (let* ((origin (current-buffer))
         (groups (jetpacs-transient--groups prefix))
         (infixes (cl-loop for (_d . kids) in groups
                           append (cl-remove 'suffix kids
                                             :key (lambda (k)
                                                    (plist-get k :kind)))))
         (nodes+ids (jetpacs-transient--infix-nodes prefix infixes))
         (ids (cdr nodes+ids))
         (capture (mapcar #'car ids))
         (body
          (cl-loop
           for (desc . kids) in groups
           append
           (delq nil
                 (cons
                  (and desc (jetpacs-section-header desc))
                  (mapcar
                   (lambda (k)
                     (pcase (plist-get k :kind)
                       ('infix (pop (car nodes+ids)))
                       ('suffix (jetpacs-button
                                 (plist-get k :description)
                                 (jetpacs-dialog-submit
                                  :value (symbol-name (plist-get k :command))
                                  :capture-fields capture)
                                 :variant "outlined"))))
                   kids)))))
         (conclusion (jetpacs-dialog--ask
                      (apply #'jetpacs-dialog--frame
                             (capitalize (replace-regexp-in-string
                                          "-" " " (symbol-name prefix)))
                             body)))
         ;; NOT `jetpacs-dialog--submitted-value': that helper quits on
         ;; dismissal, which is right for a question and wrong for a
         ;; menu — closing a menu is a normal outcome, not a C-g.
         (value (and (equal (nth 0 conclusion) "submitted")
                     (plist-get (nth 1 conclusion) :value))))
    (when (stringp value)
      (let* ((fields (plist-get (nth 1 conclusion) :fields))
             (args (jetpacs-transient--args-from-fields fields ids))
             (cmd (intern-soft value)))
        (setf (alist-get prefix jetpacs-transient--values) args)
        (when (commandp cmd)
          (with-current-buffer (if (buffer-live-p origin)
                                   origin (current-buffer))
            ;; The suffix reads (transient-args PREFIX); hand it the
            ;; captured fields exactly as transient state would look.
            (cl-letf (((symbol-function 'transient-args)
                       (lambda (_prefix) args)))
              (call-interactively cmd))))))))

(defun jetpacs-transient--setup (orig &optional name &rest args)
  "Bridge `transient-setup' to a dialog in a device flow.
Outside one — or for a NAME-less internal call — pass through."
  (if (and name (jetpacs-dialog--bridge-p))
      (jetpacs-transient--show name)
    (apply orig name args)))

(defun jetpacs-transient-install ()
  "Advise `transient-setup'.  Idempotent; a passthrough on desktop."
  (advice-add 'transient-setup :around #'jetpacs-transient--setup))

(defun jetpacs-transient-uninstall ()
  "Remove the `transient-setup' advice."
  (advice-remove 'transient-setup #'jetpacs-transient--setup))

(jetpacs-transient-install)

(provide 'jetpacs-transient)
;;; jetpacs-transient.el ends here