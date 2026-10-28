;;; glasspane-vulpea.el --- Mobile-context vulpea extractor -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;; Indexes Tasker/Mobile context properties (LOCATION, WIFI_SSID,
;; BATTERY_LEVEL, ACTIVITY, BLUETOOTH_DEVICES) into a `glasspane_mobile'
;; plugin table riding the user's vulpea note index (vulpea 2.6 extractor
;; API).  Rows are keyed to the note id with a cascade foreign key, so
;; vulpea's own delete-then-reinsert file update and file removals clean
;; them — no delete hook.
;;
;; This file is the extractor's `:worker-lib': vulpea's extraction worker
;; `require's it to resolve the extract-fn in its own process, so loading
;; it must have no side effects — definitions only.  Registration (which
;; applies the plugin schema, DDL only the main process may run) happens
;; through `glasspane-vulpea-register', called where Glasspane detects
;; vulpea: the glasspane-org load tail (G1) and the packages light-up
;; (G2).  vulpea is never installed on the CI Emacs: the `ext:'
;; declarations below keep `byte-compile-error-on-warn' honest with it
;; absent (PLAN-glasspane-app.md, banked traps), and the guard in
;; `glasspane-vulpea-register' stays the cheap `fboundp' probe — this
;; file must never be the thing that loads vulpea.

;;; Code:

(require 'cl-lib)
(require 'org)

(defvar ebp-org-note-query-terms)
(defvar org-element-cache-persistent)
(declare-function ebp-org-matches-p "ebp-org" (tree get-fn))
(declare-function ebp-org-done-keyword-p "ebp-org" (keyword))
(declare-function emacsql "ext:emacsql" (connection sql &rest args))
(declare-function vulpea-db "ext:vulpea-db" ())
(declare-function vulpea-db-register-extractor "ext:vulpea-db-extract"
                  (extractor-or-name &optional fn))
(declare-function make-vulpea-extractor "ext:vulpea-db-extract" (&rest slots))
(declare-function vulpea-note-todo "ext:vulpea-note" (note))
(declare-function vulpea-note-closed "ext:vulpea-note" (note))
(declare-function vulpea-note-tags "ext:vulpea-note" (note))
(declare-function vulpea-note-priority "ext:vulpea-note" (note))
(declare-function vulpea-note-title "ext:vulpea-note" (note))
(declare-function vulpea-note-level "ext:vulpea-note" (note))
(declare-function vulpea-note-properties "ext:vulpea-note" (note))
(declare-function vulpea-note-deadline "ext:vulpea-note" (note))
(declare-function vulpea-note-scheduled "ext:vulpea-note" (note))
(declare-function vulpea-note-path "ext:vulpea-note" (note))
(declare-function vulpea-note-outline-path "ext:vulpea-note" (note))
(declare-function vulpea-db-query "ext:vulpea-db" (&optional pred))
(declare-function vulpea-db-query-by-directory "ext:vulpea-db" (dir &optional level))

(defun glasspane-vulpea--note-get (note what &rest args)
  "The grammar accessor over a `vulpea-note' NOTE (index only, no visit)."
  (pcase what
    ('todo (vulpea-note-todo note))
    ('done (let ((s (vulpea-note-todo note)))
             (or (ebp-org-done-keyword-p s)
                 (and (vulpea-note-closed note) t))))
    ('tags (vulpea-note-tags note))
    ('priority (let ((p (vulpea-note-priority note)))
                 (cond ((null p) nil)
                       ((characterp p) p)
                       ((and (stringp p) (> (length p) 0)) (aref p 0))
                       (t (let ((s (format "%s" p)))
                            (and (> (length s) 0) (aref s 0)))))))
    ('title (vulpea-note-title note))
    ('level (vulpea-note-level note))
    ('property (cdr (assoc-string (car args) (vulpea-note-properties note) t)))
    ('planning (let ((s (if (equal (car args) "DEADLINE")
                            (vulpea-note-deadline note)
                          (vulpea-note-scheduled note))))
                 (and (stringp s) s)))
    ('habit (equal "habit"
                   (cdr (assoc-string "STYLE" (vulpea-note-properties note) t))))
    ('regexp-match
     (let ((hay (concat (or (vulpea-note-title note) "") " "
                        (mapconcat #'cdr (vulpea-note-properties note) " ")))
           (case-fold-search t))
       (string-match-p (car args) hay)))))

(defun ebp-org-note-matches-p (tree note)
  "Non-nil when `vulpea-note' NOTE matches query sexp TREE.
The same grammar as `ebp-org-entry-matches-p', evaluated entirely
off the vulpea index (no file visit); the `regexp' term searches
title + properties here (the body is not indexed)."
  (ebp-org-matches-p
   tree (lambda (what &rest args)
          (apply #'glasspane-vulpea--note-get note what args))))

(defun ebp-org-note-query-supported-p (tree)
  "Non-nil when query sexp TREE uses only index-evaluable terms.
Empty (nil) TREE — no filter — is trivially supported."
  (pcase tree
    ('nil t)
    (`(and . ,cs) (cl-every #'ebp-org-note-query-supported-p cs))
    (`(or . ,cs) (cl-every #'ebp-org-note-query-supported-p cs))
    (`(not ,c) (ebp-org-note-query-supported-p c))
    (`(,head . ,_) (and (memq head ebp-org-note-query-terms) t))
    (_ nil)))

(defun glasspane-vulpea-available-p ()
  "Non-nil when the vulpea note index is loadable on this Emacs."
  (and (require 'vulpea nil t) (fboundp 'vulpea-db-query) t))

(defun glasspane-vulpea-source-notes (source)
  "The `vulpea-note' records backing SOURCE, a scope plist."
  (let ((dir (plist-get source :dir))
        (file (plist-get source :file))
        (heading (plist-get source :heading)))
    (cond
     (dir (vulpea-db-query-by-directory (directory-file-name dir) 0))
     (file
      (let ((want (expand-file-name file)))
        (vulpea-db-query
         (lambda (n)
           (and (equal (expand-file-name (vulpea-note-path n)) want)
                (if heading
                    (equal (vulpea-note-outline-path n) (list heading))
                  (= (vulpea-note-level n) 1)))))))
     (t (user-error "Source needs :dir or :file: %S" source)))))

(defun glasspane-vulpea-query (source &optional tree)
  "Notes of SOURCE matching query sexp TREE, off the vulpea index."
  (let ((notes (glasspane-vulpea-source-notes source)))
    (if tree
        (cl-remove-if-not (lambda (n) (ebp-org-note-matches-p tree n)) notes)
      notes)))

(defun glasspane-vulpea--extract-mobile (_ctx note-data)
  "Index NOTE-DATA's mobile context properties into `glasspane_mobile'.
Runs per note, inside vulpea's file-update transaction, after the note
row is inserted — so the row it writes can hold a foreign key against
the note.  Props-only: never reads the AST, which keeps the extractor
worker-eligible.  Returns NOTE-DATA unchanged (side-effecting
extractor)."
  (let* ((props (plist-get note-data :properties))
         (id (plist-get note-data :id))
         (location (cdr (assoc "LOCATION" props)))
         (wifi (cdr (assoc "WIFI_SSID" props)))
         (battery (cdr (assoc "BATTERY_LEVEL" props)))
         (activity (cdr (assoc "ACTIVITY" props)))
         (bluetooth (cdr (assoc "BLUETOOTH_DEVICES" props))))
    (when (and id (or location wifi battery activity bluetooth))
      (emacsql (vulpea-db)
               [:insert :into glasspane-mobile :values $v1]
               (vector id location wifi
                       (and battery (string-to-number battery))
                       activity bluetooth)))
    note-data))

;;;; Parsing without Org's persistent element cache
;;
;; Vulpea parses a file in one reused scratch buffer whose
;; `buffer-file-name' it sets to the file for the parse, then resets that
;; buffer's element cache.  With `org-element-cache-persistent' on,
;; the reset registers the cache with org-persist under the file, and
;; org-persist loads the stored cache into the buffer VISITING that file,
;; the user's own buffer.  That buffer's live cache is swapped for a stale
;; tree, and the next `org-element-cache-map' over it (an agenda scan)
;; never terminates.  Seen on the tablet after any save Vulpea re-indexed
;; (2026-10-28, Org 9.8.3, vulpea 20260813).  The scratch parse gains
;; nothing from persistence, so it runs without it.

(defun glasspane-vulpea--parse-unpersisted (parse &rest args)
  "Call PARSE with ARGS while Org's element cache is not persisted.
Around advice for `vulpea-db--parse-file'; see the section comment."
  (let ((org-element-cache-persistent nil))
    (apply parse args)))

(defun glasspane-vulpea-guard-parses ()
  "Keep Vulpea's in-process parses away from Org's persistent cache.
Idempotent; advising an as-yet-undefined function is fine, the advice
applies once Vulpea's extractor loads."
  (advice-add 'vulpea-db--parse-file :around
              #'glasspane-vulpea--parse-unpersisted))

(defun glasspane-vulpea-unguard-parses ()
  "Undo `glasspane-vulpea-guard-parses' (the app's teardown)."
  (advice-remove 'vulpea-db--parse-file #'glasspane-vulpea--parse-unpersisted))

(defvar glasspane-vulpea--registered nil
  "Non-nil once the mobile extractor has been registered this session.")

(defun glasspane-vulpea-register ()
  "Register the mobile-context extractor with vulpea (idempotent).
Creates the plugin table via the extractor `:schema'; the cascade
foreign key keeps it consistent from then on.  A no-op when vulpea's
extractor registry isn't loaded — Glasspane never force-loads vulpea,
it only rides an index the user's own config (or the packages
light-up) brought up."
  (glasspane-vulpea-guard-parses)
  (when (and (not glasspane-vulpea--registered)
             (fboundp 'vulpea-db-register-extractor))
    (vulpea-db-register-extractor
     (apply #'make-vulpea-extractor
            :name 'glasspane-mobile
            :version 1
            :priority 90
            :schema '((glasspane-mobile
                       [(note-id :not-null) location wifi battery activity bluetooth]
                       (:foreign-key [note-id] :references notes [id]
                        :on-delete :cascade)))
            :extract-fn #'glasspane-vulpea--extract-mobile
            ;; The declaration trio shipped together in vulpea 2.6's
            ;; extractor struct: explicit `:requires-ast nil' (default is
            ;; the `unset' sentinel) pins the props-only contract so
            ;; extraction never forces a full object parse, and
            ;; `:worker-safe'/`:worker-lib' keep it eligible for the
            ;; async worker.  Probed because pre-2.6 vulpea has none of
            ;; these slots — a cl-defstruct constructor signals on
            ;; unknown keywords (the exact load-crash this rewrite
            ;; fixes), and pre-2.6 always populates the AST and has no
            ;; worker, so omitting them there is correct, not degraded.
            (when (fboundp 'vulpea-extractor-requires-ast-p)
              '(:requires-ast nil :worker-safe t :worker-lib glasspane-vulpea))))
    (setq glasspane-vulpea--registered t)))

(provide 'glasspane-vulpea)
;;; glasspane-vulpea.el ends here
