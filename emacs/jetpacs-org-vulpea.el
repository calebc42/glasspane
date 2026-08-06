;;; jetpacs-org-vulpea.el --- Vulpea note-index arm for the org grammar -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; TIER-1 STAGING, not base.  Ratified (Caleb, 2026-07-27): base
;; Jetpacs is vanilla Emacs optimized for mobile (the R2 frame), and
;; vulpea is a third-party package — so the note-index engine arm lives
;; ABOVE the base boundary.  This file stages it in the rewrite's idiom
;; until the Tier-1 rung that consumes it exists (the PKM layer:
;; glasspane / orgseq territory), at which point it migrates to the app
;; repo.  NO base module may ever require it.
;;
;; What base provides instead is the seam: `jetpacs-org-matches-p' is
;; accessor-pluggable, and this file is its first above-base consumer —
;; the same vetted grammar evaluated off the vulpea index (no file
;; visit) rather than at point.  vulpea is never required at load;
;; callers gate on `jetpacs-org-vulpea-available-p'.  The "ext:"
;; pseudo-file keeps `byte-compile-error-on-warn' honest without vulpea
;; on the load path (the sections/magit-section shape).
;;
;; NAMING, decided deliberately.  This file's PRIVATE helpers carry the
;; arm's own `jetpacs-org-vulpea--' prefix: an arm that defines a
;; symbol in base's private namespace (`jetpacs-org--…') squats a name
;; base owns, and the collision lands silently the moment base grows
;; its own.  The two PUBLIC entry points below deliberately do NOT
;; take the arm's prefix — `jetpacs-org-note-matches-p' and
;; `jetpacs-org-note-query-supported-p' name the note-index PROTOCOL,
;; not vulpea: a second index backend (a plain org-id scan, a sqlite
;; cache) implements those same two names and swaps in underneath its
;; callers unchanged.  Do not "fix" them to `jetpacs-org-vulpea-'.

;;; Code:

(require 'cl-lib)
(require 'org)                          ; org-done-keywords
(require 'jetpacs-org)                  ; the interpreter seam + allowlist

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

(defun jetpacs-org-vulpea--note-get (note what &rest args)
  "The grammar accessor over a `vulpea-note' NOTE (index only, no visit)."
  (pcase what
    ('todo (vulpea-note-todo note))
    ;; The index carries no per-file DONE keyword set: done-ness is a
    ;; global done keyword (falling back to the near-universal \"DONE\"
    ;; in a headless scan) or a CLOSED stamp.
    ('done (let ((s (vulpea-note-todo note)))
             (or (and s (member s (or org-done-keywords '("DONE"))) t)
                 (and (vulpea-note-closed note) t))))
    ('tags (vulpea-note-tags note))
    ;; vulpea priority may be a char (org's native form) or a string.
    ('priority (let ((p (vulpea-note-priority note)))
                 (cond ((null p) nil)
                       ((characterp p) p)
                       ((and (stringp p) (> (length p) 0)) (aref p 0))
                       (t (let ((s (format "%s" p)))
                            (and (> (length s) 0) (aref s 0)))))))
    ('title (vulpea-note-title note))
    ('level (vulpea-note-level note))
    ;; vulpea indexes drawer keys upper-cased; match case-insensitively.
    ('property (cdr (assoc-string (car args) (vulpea-note-properties note) t)))
    ('planning (let ((s (if (equal (car args) "DEADLINE")
                            (vulpea-note-deadline note)
                          (vulpea-note-scheduled note))))
                 (and (stringp s) s)))
    ('habit (equal "habit"
                   (cdr (assoc-string "STYLE" (vulpea-note-properties note) t))))
    ('regexp-match
     ;; The index haystack is title + properties — the body is not
     ;; indexed.  SEMANTIC DIFFERENCE from the point accessor, by design.
     (let ((hay (concat (or (vulpea-note-title note) "") " "
                        (mapconcat #'cdr (vulpea-note-properties note) " ")))
           (case-fold-search t))
       (string-match-p (car args) hay)))))

(defun jetpacs-org-note-matches-p (tree note)
  "Non-nil when `vulpea-note' NOTE matches query sexp TREE.
The same grammar as `jetpacs-org-entry-matches-p', evaluated entirely
off the vulpea index (no file visit); the `regexp' term searches
title + properties here (the body is not indexed)."
  (jetpacs-org-matches-p
   tree (lambda (what &rest args)
          (apply #'jetpacs-org-vulpea--note-get note what args))))

(defun jetpacs-org-note-query-supported-p (tree)
  "Non-nil when query sexp TREE uses only index-evaluable terms.
Empty (nil) TREE — no filter — is trivially supported."
  (pcase tree
    ('nil t)
    (`(and . ,cs) (cl-every #'jetpacs-org-note-query-supported-p cs))
    (`(or . ,cs) (cl-every #'jetpacs-org-note-query-supported-p cs))
    (`(not ,c) (jetpacs-org-note-query-supported-p c))
    (`(,head . ,_) (and (memq head jetpacs-org-note-query-terms) t))
    (_ nil)))

;;;; The note-index entry points

(defun jetpacs-org-vulpea-available-p ()
  "Non-nil when the vulpea note index is loadable on this Emacs.
vulpea is never required at load; callers gate their index reads here.
Probing DOES load vulpea when present."
  (and (require 'vulpea nil t) (fboundp 'vulpea-db-query) t))

(defun jetpacs-org-vulpea-source-notes (source)
  "The `vulpea-note' records backing SOURCE, a scope plist.
SOURCE is one of:
  (:dir D)               -> the file-level notes of vault directory D;
  (:file F :heading H)   -> the id'd headings directly under H in F;
  (:file F)              -> the id'd level-1 headings of F.
Headings must already carry `:ID:' properties for the index to see
them.  Callers gate on `jetpacs-org-vulpea-available-p'."
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

(defun jetpacs-org-vulpea-query (source &optional tree)
  "Notes of SOURCE matching query sexp TREE, off the vulpea index.
A nil TREE admits every note of the scope.  TREE must stay inside
`jetpacs-org-note-query-terms' — check
`jetpacs-org-note-query-supported-p' first."
  (let ((notes (jetpacs-org-vulpea-source-notes source)))
    (if tree
        (cl-remove-if-not (lambda (n) (jetpacs-org-note-matches-p tree n)) notes)
      notes)))

(provide 'jetpacs-org-vulpea)
;;; jetpacs-org-vulpea.el ends here
