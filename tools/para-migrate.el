;;; para-migrate.el --- Migrate an Org vault to Glasspane's PARA model -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; PM-7 of docs/PLAN-glasspane-para.md.  A dry-run-by-default, idempotent
;; migration of one Org vault to the 2026-09-04 PARA model:
;;
;;   1. repair malformed `#+TAGS:' / `#+FILETAGS:' lines;
;;   2. rename `AREA' property drawers whose value is not an Area (the
;;      résumé "area of study" collision) to another key;
;;   3. rename the whole-file `:project:' filetag to `:workspace:';
;;   4. seed the Area tag group into `org-tag-persistent-alist' through
;;      the host settings writer, after printing per-Area member counts;
;;   5. optionally scaffold one declaring heading per Area (`:scaffold t').
;;
;; Loading this file has no side effects.  Run it on the desktop in batch
;; (the command line is recorded under PM-7 in docs/PLAN-glasspane-para.md)
;; and on the tablet from the Eval REPL after `load'-ing it.  Nothing is
;; written until `:write t'; every step recomputes its precondition from
;; disk, so a second write run reports only SKIP lines.  A line the script
;; cannot fully parse is reported, never rewritten.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'org)
(require 'org-id)

(declare-function jetpacs-org-settings-set-tag-group-members
                  "ext:jetpacs-org-settings" (group members &optional variable))

(defvar glasspane-para-migrate-default-members
  '("tech" "career" "meta" "sovereignty" "computing")
  "Area vocabulary seeded when the caller supplies no MEMBERS.")

(defvar glasspane-para-migrate-collision-key "FIELD_OF_STUDY"
  "Property key that replaces an AREA drawer whose value is not an Area.")

(defvar glasspane-para-migrate-exclude-regexp
  "/\\(?:\\.[^/]\\|projects/\\|sites/\\|resources/emacs/\\)"
  "Paths matching this regexp are never scanned or rewritten.")

(defvar glasspane-para-migrate--log nil
  "Report lines of the current run, newest first.")

(defun glasspane-para-migrate--say (fmt &rest args)
  "Record and print FMT formatted with ARGS."
  (let ((line (apply #'format fmt args)))
    (push line glasspane-para-migrate--log)
    (if noninteractive
        (princ (concat line "\n"))
      (with-current-buffer (get-buffer-create "*para-migrate*")
        (goto-char (point-max))
        (insert line "\n")))))

;;;; Files

(defun glasspane-para-migrate--files (dir)
  "Return the vault DIR's Org files, excluding checkouts and lock files."
  (cl-remove-if
   (lambda (file)
     (or (string-match-p glasspane-para-migrate-exclude-regexp file)
         (string-prefix-p ".#" (file-name-nondirectory file))
         (not (file-regular-p file))
         (not (file-readable-p file))))
   (directory-files-recursively dir "\\.org\\'")))

(defun glasspane-para-migrate--agenda-files (dir)
  "Return the top-level Org files of DIR: the non-recursive agenda scope."
  (directory-files dir t "\\.org\\'"))

(defun glasspane-para-migrate--read (file)
  "Return FILE's lines as a list of strings."
  (with-temp-buffer
    (insert-file-contents file)
    (split-string (buffer-string) "\n")))

(defun glasspane-para-migrate--write-lines (file lines)
  "Write LINES back to FILE."
  (with-temp-file file
    (insert (string-join lines "\n"))))

(defun glasspane-para-migrate--apply (file edits write)
  "Report EDITS to FILE as (LINE-NUMBER OLD NEW REASON); write when WRITE."
  (when edits
    (let ((lines (glasspane-para-migrate--read file)))
      (dolist (edit edits)
        (pcase-let ((`(,n ,old ,new ,reason) edit))
          (glasspane-para-migrate--say "%s %s:%d %s\n    - %s\n    + %s"
                                       (if write "WROTE:" "PLAN: ")
                                       (abbreviate-file-name file) n reason
                                       old new)
          (when write
            (unless (equal (nth (1- n) lines) old)
              (error "%s:%d changed under the migration" file n))
            (setf (nth (1- n) lines) new))))
      (when write
        (glasspane-para-migrate--write-lines file lines)))))

;;;; Step 1 — malformed tag lines

(defconst glasspane-para-migrate--tag-token-re
  (concat "\\`" org-tag-re "\\(?:([^)]*)\\)?\\'")
  "A single `#+TAGS:' token: a tag with an optional fast-selection key.")

(defun glasspane-para-migrate--normalize-tag (word)
  "Return WORD as a legal tag, or nil when it cannot be one."
  (let ((clean (replace-regexp-in-string "-" "_" (string-trim word ",\\s-*" ",\\s-*"))))
    (and (not (string-empty-p clean))
         (string-match-p (concat "\\`" org-tag-re "\\'") clean)
         clean)))

(defun glasspane-para-migrate--fix-filetags (value)
  "Return a corrected `#+FILETAGS:' VALUE, or nil when it is already fine.
Signals `user-error' when the line cannot be repaired mechanically."
  (let ((v (string-trim value)))
    (cond
     ((string-match-p "\\`:\\(?:[^: \t]+:\\)+\\'" v) nil)
     ((string-match-p "\\`:[^ \t]+\\'" v)
      (concat v ":"))
     ((string-match-p "\\`[^:]" v)
      (let ((tags (mapcar #'glasspane-para-migrate--normalize-tag
                          (split-string v "[ \t,]+" t))))
        (if (memq nil tags)
            (user-error "Unparseable FILETAGS %S" v)
          (concat ":" (string-join tags ":") ":"))))
     (t (user-error "Unparseable FILETAGS %S" v)))))

(defun glasspane-para-migrate--fix-tags (value)
  "Return a corrected `#+TAGS:' VALUE, or nil when it is already fine."
  (let* ((v (string-trim value))
         (structural '("{" "}" "[" "]" ":" "\\"))
         (words (split-string v "[ \t]+" t)))
    (cond
     ;; FILETAGS syntax on a TAGS line: `:a: :b:' or `:a:b:'.
     ((and (string-prefix-p ":" v)
           (not (cl-some (lambda (w) (member w structural)) words)))
      (let ((tags (mapcar #'glasspane-para-migrate--normalize-tag
                          (split-string v "[: \t]+" t))))
        (if (memq nil tags)
            (user-error "Unparseable TAGS %S" v)
          (string-join tags " "))))
     ((cl-every (lambda (w)
                  (or (member w structural)
                      (string-match-p glasspane-para-migrate--tag-token-re w)))
                words)
      nil)
     (t
      (let ((tags (mapcar (lambda (w)
                            (if (member w structural) w
                              (glasspane-para-migrate--normalize-tag w)))
                          words)))
        (if (memq nil tags)
            (user-error "Unparseable TAGS %S" v)
          (string-join tags " ")))))))

(defun glasspane-para-migrate--tag-line-edits (file)
  "Return the tag-keyword repairs FILE needs."
  (let ((n 0) edits)
    (dolist (line (glasspane-para-migrate--read file))
      (setq n (1+ n))
      (when (string-match "\\`\\([ \t]*#\\+\\(FILETAGS\\|TAGS\\):\\)[ \t]*\\(.*\\)\\'"
                          line)
        (let* ((prefix (match-string 1 line))
               (kind (upcase (match-string 2 line)))
               (value (match-string 3 line))
               (fixed (condition-case err
                          (if (equal kind "FILETAGS")
                              (glasspane-para-migrate--fix-filetags value)
                            (glasspane-para-migrate--fix-tags value))
                        (user-error
                         (glasspane-para-migrate--say
                          "MANUAL: %s:%d %s — %s"
                          (abbreviate-file-name file) n line
                          (error-message-string err))
                         nil))))
          (when fixed
            (push (list n line (concat prefix " " fixed)
                        (format "repair #+%s syntax%s" kind
                                (if (string-match-p "-" value)
                                    " (hyphen is not a tag character: -> _)"
                                  "")))
                  edits)))))
    (nreverse edits)))

;;;; Step 2 — AREA collisions

(defun glasspane-para-migrate--area-collision-edits (file members)
  "Return the AREA-drawer renames FILE needs for values outside MEMBERS."
  (let ((n 0) edits)
    (dolist (line (glasspane-para-migrate--read file))
      (setq n (1+ n))
      (when (string-match "\\`\\([ \t]*\\):AREA:\\([ \t]+\\)\\(.*\\)\\'" line)
        (let ((value (string-trim (match-string 3 line))))
          (unless (member value members)
            (push (list n line
                        (concat (match-string 1 line) ":"
                                glasspane-para-migrate-collision-key ":"
                                (match-string 2 line) (match-string 3 line))
                        (format "AREA value %S is not an Area" value))
                  edits)))))
    (nreverse edits)))

;;;; Step 3 — :project: filetags become :workspace:

(defun glasspane-para-migrate--workspace-edits (file)
  "Return the `:project:' -> `:workspace:' filetag renames FILE needs."
  (let ((n 0) edits)
    (dolist (line (glasspane-para-migrate--read file))
      (setq n (1+ n))
      (cond
       ((and (string-match-p "\\`[ \t]*#\\+FILETAGS:" line)
             (string-match-p ":project:" line))
        (push (list n line (replace-regexp-in-string ":project:" ":workspace:" line t t)
                    "whole-file :project: means workspace")
              edits))
       ((and (string-match-p "\\`\\*+ " line)
             (string-match-p ":project:" line))
        (glasspane-para-migrate--say
         "NOTE: %s:%d heading-level :project: tag left alone"
         (abbreviate-file-name file) n))))
    (nreverse edits)))

;;;; Step 4 — vocabulary and counts

(defun glasspane-para-migrate--scan-members (file members)
  "Return FILE's counts per member of MEMBERS.
Each row is (MEMBER FILE-TAG HEADINGS OPEN)."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((org-use-tag-inheritance t))
      (delay-mode-hooks (org-mode))
      (let ((rows (mapcar (lambda (m) (list m nil 0 0)) members)))
        (org-map-entries
         (lambda ()
           (let ((tags (org-get-tags))
                 (open (and (org-get-todo-state)
                            (not (org-entry-is-done-p)))))
             (dolist (row rows)
               (when (member (car row) tags)
                 (cl-incf (nth 2 row))
                 (when open (cl-incf (nth 3 row)))))))
         nil nil)
        (dolist (row rows)
          (setf (nth 1 row) (and (member (car row) org-file-tags) t)))
        rows))))

(defun glasspane-para-migrate--report-members (dir files members)
  "Print the per-Area counts over FILES for MEMBERS, marking DIR's scope."
  (let ((scope (mapcar #'file-truename
                       (glasspane-para-migrate--agenda-files dir)))
        (totals (mapcar (lambda (m) (list m 0 0 0 0)) members)))
    (dolist (file files)
      (let ((in-scope (member (file-truename file) scope)))
        (dolist (row (condition-case nil
                         (glasspane-para-migrate--scan-members file members)
                       (error nil)))
          (let ((total (assoc (car row) totals)))
            (when (or (nth 1 row) (> (nth 2 row) 0))
              (cl-incf (nth 1 total))
              (unless in-scope (cl-incf (nth 4 total))))
            (cl-incf (nth 2 total) (nth 2 row))
            (cl-incf (nth 3 total) (nth 3 row))))))
    (glasspane-para-migrate--say "AREA MEMBERS (files / headings / open TODOs):")
    (dolist (total totals)
      (glasspane-para-migrate--say
       "  %-14s %3d files  %4d headings  %4d open%s"
       (nth 0 total) (nth 1 total) (nth 2 total) (nth 3 total)
       (if (> (nth 4 total) 0)
           (format "   (%d file%s outside the non-recursive agenda scope)"
                   (nth 4 total) (if (= (nth 4 total) 1) "" "s"))
         "")))))

(defun glasspane-para-migrate--current-members (custom)
  "Return the Area group's current members from both alists.
In a fresh batch session the saved value lives only in CUSTOM (or
`custom-file'), so that file is loaded first when it exists."
  (let ((saved (or custom custom-file)))
    (when (and (stringp saved) (file-exists-p saved))
      (ignore-errors (load saved t t))))
  (condition-case nil
      (cdr (assoc-string
            "Area"
            (org-tag-alist-to-groups
             (append org-tag-persistent-alist org-tag-alist))
            t))
    (error nil)))

(defun glasspane-para-migrate--seed (members write custom)
  "Seed MEMBERS as the Area group in `org-tag-persistent-alist'.
Writes only when WRITE; CUSTOM overrides `custom-file' for the save."
  (let ((sexp (format "(setq org-tag-persistent-alist\n      '(%s))"
                      (mapconcat #'prin1-to-string
                                 (append '((:startgrouptag) ("Area") (:grouptags))
                                         (mapcar #'list members)
                                         '((:endgrouptag)))
                                 "\n        "))))
    (cond
     ((equal (glasspane-para-migrate--current-members custom) members)
      (glasspane-para-migrate--say "SKIP (already): Area group = %S" members))
     ((not write)
      (glasspane-para-migrate--say "PLAN:  seed Area group %S into org-tag-persistent-alist" members))
     ((not (and (require 'jetpacs-org-settings nil t)
                (fboundp 'jetpacs-org-settings-set-tag-group-members)))
      (glasspane-para-migrate--say "MANUAL: jetpacs-org-settings is not loadable here; add to your init:\n%s" sexp))
     ((not (or custom custom-file))
      (glasspane-para-migrate--say "MANUAL: custom-file is nil, refusing to edit the init file; pass :custom-file or add to your init:\n%s" sexp))
     (t
      ;; Customize refuses to save while `user-init-file' is nil (a -Q
      ;; batch session); naming the custom file as the init file is what
      ;; tells it where the settings live.  `--current-members' has
      ;; already loaded that file, so its other saved values survive the
      ;; rewrite.
      (let* ((custom-file (or custom custom-file))
             (user-init-file (or user-init-file custom-file)))
        (jetpacs-org-settings-set-tag-group-members
         "Area" members 'org-tag-persistent-alist)
        (glasspane-para-migrate--say "WROTE: Area group %S -> org-tag-persistent-alist (saved to %s)"
                                     members (abbreviate-file-name custom-file)))))
    (glasspane-para-migrate--say "  equivalent init form:\n%s" sexp)))

;;;; Step 5 — scaffold declaring notes (opt-in)

(defun glasspane-para-migrate--declared (files)
  "Return the AREA values declared anywhere in FILES."
  (let (declared)
    (dolist (file files)
      (dolist (line (glasspane-para-migrate--read file))
        (when (string-match "\\`[ \t]*:AREA:[ \t]+\\(.+?\\)[ \t]*\\'" line)
          (cl-pushnew (match-string 1 line) declared :test #'equal))))
    declared))

(defun glasspane-para-migrate--scaffold (dir files members write)
  "Ensure DIR/areas.org declares every member of MEMBERS lacking a note.
FILES is the vault's Org file set.  Writes only when WRITE."
  (let* ((target (expand-file-name "areas.org" dir))
         (declared (glasspane-para-migrate--declared files))
         (missing (cl-remove-if (lambda (m) (member m declared)) members)))
    (if (null missing)
        (glasspane-para-migrate--say "SKIP (already): every Area has a declaring note")
      (glasspane-para-migrate--say "%s declare %S in %s"
                                   (if write "WROTE:" "PLAN: ")
                                   missing (abbreviate-file-name target))
      (when write
        (with-temp-buffer
          (when (file-exists-p target)
            (insert-file-contents target))
          (goto-char (point-max))
          (when (= (point-min) (point-max))
            (insert "#+TITLE: Areas\n\n"))
          (unless (bolp) (insert "\n"))
          (dolist (m missing)
            (insert (format "* %s :%s:\n:PROPERTIES:\n:ID:       %s\n:AREA: %s\n:END:\n\n"
                            (capitalize m) m (org-id-new) m)))
          (write-region (point-min) (point-max) target))))))

;;;; Entry point

(defun glasspane-para-migrate--dirty-p (dir)
  "Return non-nil when DIR is a git work tree with uncommitted changes."
  (and (executable-find "git")
       (file-directory-p (expand-file-name ".git" dir))
       (with-temp-buffer
         (let ((default-directory dir))
           (and (= 0 (call-process "git" nil t nil "status" "--porcelain"))
                (> (buffer-size) 0))))))

;;;###autoload
(cl-defun glasspane-para-migrate (dir &key write scaffold ((:custom-file custom))
                                      members force)
  "Migrate the Org vault at DIR to the PARA model; dry-run unless WRITE.
SCAFFOLD adds declaring headings to DIR/areas.org.  CUSTOM-FILE (the
`:custom-file' keyword, bound as CUSTOM) names the file the tag-group save
goes to.  MEMBERS is the Area vocabulary (default
`glasspane-para-migrate-default-members').  FORCE allows writing into a
git tree with uncommitted changes.  Returns the report lines."
  (interactive (list (read-directory-name "Vault: " org-directory)))
  (setq glasspane-para-migrate--log nil)
  (let* ((dir (file-name-as-directory (expand-file-name dir)))
         (members (or members glasspane-para-migrate-default-members))
         (files (glasspane-para-migrate--files dir)))
    (unless (file-directory-p dir)
      (user-error "Not a directory: %s" dir))
    (glasspane-para-migrate--say "para-migrate %s: %d Org files, %s"
                                 (abbreviate-file-name dir) (length files)
                                 (if write "WRITE MODE" "dry run"))
    (when (and write (not force) (glasspane-para-migrate--dirty-p dir))
      (user-error "%s has uncommitted changes; commit them or pass :force t" dir))
    (glasspane-para-migrate--say "-- 1. tag keyword syntax")
    (dolist (file files)
      (glasspane-para-migrate--apply
       file (glasspane-para-migrate--tag-line-edits file) write))
    (glasspane-para-migrate--say "-- 2. AREA drawers that are not Areas")
    (dolist (file files)
      (glasspane-para-migrate--apply
       file (glasspane-para-migrate--area-collision-edits file members) write))
    (glasspane-para-migrate--say "-- 3. :project: filetags -> :workspace:")
    (dolist (file files)
      (glasspane-para-migrate--apply
       file (glasspane-para-migrate--workspace-edits file) write))
    (glasspane-para-migrate--say "-- 4. Area vocabulary")
    (glasspane-para-migrate--report-members dir files members)
    (glasspane-para-migrate--seed members write custom)
    (when scaffold
      (glasspane-para-migrate--say "-- 5. declaring notes")
      (glasspane-para-migrate--scaffold dir files members write))
    (when (fboundp 'ebp-org-cache-invalidate)
      (ebp-org-cache-invalidate))
    (glasspane-para-migrate--say "done.")
    (unless noninteractive
      (display-buffer "*para-migrate*"))
    (reverse glasspane-para-migrate--log)))

(provide 'para-migrate)
;;; para-migrate.el ends here
