;;; m3-check.el --- per-component gate for the M3 catalog -*- lexical-binding: t; -*-

;;; Commentary:

;; Build and check ONE catalog component without waiting on the other
;; forty.  Run from the repo root:
;;
;;   emacs -Q --batch -L emacs -L emacs/apps/m3-catalog \
;;     -l tools/m3-check.el -f jetpacs-m3-check-batch buttons
;;
;; Checks, per component: its screen and each of its example screens
;; build, stay inside the reference `app' profile (SPEC 16.2),
;; canonicalize, carry document-unique ids (SPEC 16.1), that no
;; `:build' degraded to the "Sample failed to build" card, that no
;; example still carries the triage sentinel, and that every icon
;; literal names an icon the Companion can resolve.  Exits non-zero
;; with a report on the first component that fails.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-m3-catalog)

(defconst jetpacs-m3-check--sentinel "TODO: not yet triaged")

(defun jetpacs-m3-check--icons ()
  "Icon names the generated lookup table knows."
  (let ((names (make-hash-table :test #'equal))
        (file "docs/lookup-tables/M3-ICON-REFERENCE.org"))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (re-search-forward "^| \\([a-z_0-9]+\\) | ~Icons" nil t)
        (puthash (match-string 1) t names)))
    names))

(defun jetpacs-m3-check--collect-icons (value acc)
  "Every icon-ish string in VALUE, accumulated into ACC."
  (cond
   ((vectorp value)
    (let ((a acc)) (mapc (lambda (v) (setq a (jetpacs-m3-check--collect-icons v a))) value) a))
   ((and (consp value) (keywordp (car value)))
    (let ((p value) (a acc))
      (while p
        (let ((k (pop p)) (v (pop p)))
          (when (and (memq k '(:icon)) (stringp v)) (push v a))
          (setq a (jetpacs-m3-check--collect-icons v a))))
      a))
   ((consp value)
    (let ((a (jetpacs-m3-check--collect-icons (car value) acc)))
      (jetpacs-m3-check--collect-icons (cdr value) a)))
   (t acc)))

(defun jetpacs-m3-check-component (id icons)
  "Check component ID; return a list of problem strings (nil = clean)."
  (let* ((component (jetpacs-m3-component id))
         (problems nil))
    (if (null component)
        (list (format "%s: no such component" id))
      (let ((screens (list (cons "component"
                                 (jetpacs-m3-component-screen component nil)))))
        (cl-loop
         for example in (plist-get component :examples)
         for index from 0
         do (let ((reason (plist-get example :unsupported))
                  (name (plist-get example :name)))
              (when (equal reason jetpacs-m3-check--sentinel)
                (push (format "%s/%s: still carries the triage sentinel"
                              id name)
                      problems))
              (when (and reason (< (length reason) 21))
                (push (format "%s/%s: :unsupported reason is too terse"
                              id name)
                      problems))
              (when (plist-get example :build)
                (let ((body (jetpacs-m3--example-body example)))
                  (when (string-match-p
                         "Sample failed to build"
                         (jetpacs-node->canonical-json body))
                    (push (format "%s/%s: :build signalled" id name)
                          problems))))
              (push (cons (format "example %d" index)
                          (jetpacs-m3-example-screen component index nil))
                    screens)))
        (dolist (cell screens)
          (let ((node (cdr cell)))
            (condition-case err
                (progn
                  (jetpacs-check-profile node 'app)
                  (jetpacs-node->canonical-json node)
                  (let ((ids (jetpacs-collect-node-ids node nil)))
                    (unless (= (length ids)
                               (length (delete-dups (copy-sequence ids))))
                      (push (format "%s/%s: duplicate node ids %S"
                                    id (car cell) ids)
                            problems)))
                  (dolist (icon (delete-dups
                                 (jetpacs-m3-check--collect-icons node nil)))
                    (unless (gethash icon icons)
                      (push (format "%s/%s: icon %S is not in the lookup table"
                                    id (car cell) icon)
                            problems))))
              (error (push (format "%s/%s: %s" id (car cell)
                                   (error-message-string err))
                           problems)))))
        (nreverse problems)))))

(defun jetpacs-m3-check-batch ()
  "Batch entry: check each component id on the command line, or all."
  (let* ((args command-line-args-left)
         (ids (or args (mapcar (lambda (c) (plist-get c :id))
                               jetpacs-m3-components)))
         (icons (jetpacs-m3-check--icons))
         (problems nil))
    (setq command-line-args-left nil)
    (dolist (id ids)
      (setq problems (append problems (jetpacs-m3-check-component id icons))))
    (if problems
        (progn (dolist (p problems) (message "FAIL %s" p))
               (message "m3-check: %d problem(s) in %s"
                        (length problems) (string-join ids " "))
               (kill-emacs 1))
      (message "m3-check: OK — %s" (string-join ids " "))
      (kill-emacs 0))))

(provide 'm3-check)
;;; m3-check.el ends here
