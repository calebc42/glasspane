;;; glasspane-source-test.el --- Tests for the glasspane.org binding source -*- lexical-binding: t; -*-

;; S3.1: the `jetpacs-defsource' "glasspane.org" and its canonicalizer.
;; Proves (1) the canonicalizer maps engine-native shapes to core's
;; domain-neutral field types, (2) the registered source resolves a fixture
;; query to canonical items in batch, and (3) a `:spec' bound to it passes
;; `jetpacs-lint-view-spec' (and an out-of-schema binding fails it).

;;; Code:

(require 'glasspane-test-helpers)
(require 'glasspane-source)
(require 'jetpacs-source)
(require 'jetpacs-lint)

(ert-deftest glasspane-source-canonicalize-field-types ()
  "Raw org shapes normalize to ISO dates, list tags, and a priority letter."
  (let ((canon (glasspane-source--canonicalize
                '((headline . "Fix the server")
                  (todo . "TODO")
                  (priority . ?A)                     ; vulpea path: a char
                  (tags . ["server" "urgent"])        ; a vector
                  (scheduled . "<2026-07-13 Mon 09:00>")
                  (deadline . nil)
                  (ref . ((file . "/tmp/a.org") (pos . 1) (headline . "Fix the server")))))))
    (should (equal "Fix the server" (alist-get 'headline canon)))
    (should (equal "TODO" (alist-get 'todo canon)))
    (should (equal "A" (alist-get 'priority canon)))
    ;; tags: vector -> list of strings
    (should (equal '("server" "urgent") (alist-get 'tags canon)))
    (should (listp (alist-get 'tags canon)))
    ;; scheduled: raw org timestamp -> ISO; deadline nil stays nil
    (should (equal "2026-07-13" (alist-get 'scheduled canon)))
    (should (null (alist-get 'deadline canon)))
    ;; ref: opaque locator, passed through intact
    (should (equal 1 (alist-get 'pos (alist-get 'ref canon))))))

(ert-deftest glasspane-source-canonicalize-absent-fields ()
  "Absent optional fields stay nil so their placeholders drop cleanly."
  (let ((canon (glasspane-source--canonicalize '((headline . "Bare")))))
    (should (equal "Bare" (alist-get 'headline canon)))
    (should (null (alist-get 'todo canon)))
    (should (null (alist-get 'scheduled canon)))
    (should (null (alist-get 'priority canon)))
    ;; an absent tags vector canonicalizes to nil (empty list), never a vector
    (should (null (alist-get 'tags canon)))))

(ert-deftest glasspane-source-registered-and-owned ()
  "The source is registered under the glasspane owner with the declared fields."
  (should (jetpacs-source-p "glasspane.org"))
  (should (equal "glasspane" (jetpacs--owner-of "source" "glasspane.org")))
  (let ((fields (mapcar (lambda (f) (plist-get f :name))
                        (jetpacs-source-fields "glasspane.org"))))
    (should (member "headline" fields))
    (should (member "scheduled" fields))
    (should (member "tags" fields))
    (should (member "ref" fields))))

(ert-deftest glasspane-source-resolves-fixture-query ()
  "The source resolves a fixture query to canonical items in batch."
  (jetpacs-tests--with-search-fixture
   (let ((items (jetpacs-source-query "glasspane.org" '((query . "todo:TODO")))))
     ;; The fixture has two TODO headings ("Fix the server", "Call plumber").
     (should (= 2 (length items)))
     (let ((headlines (mapcar (lambda (it) (alist-get 'headline it)) items)))
       (should (member "Fix the server" headlines))
       (should (member "Call plumber" headlines)))
     ;; Every item is canonical: tags a list (never a vector), any scheduled/
     ;; deadline an ISO date string or nil.
     (dolist (it items)
       (should (listp (alist-get 'tags it)))
       (should (not (vectorp (alist-get 'tags it))))
       (dolist (key '(scheduled deadline))
         (let ((v (alist-get key it)))
           (should (or (null v)
                       (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" v)))))))))

(ert-deftest glasspane-source-missing-required-param-errors ()
  "Querying without the required `query' param signals, per the source schema."
  (should-error (jetpacs-source-query "glasspane.org" '())))

(defconst glasspane-source-test--fields
  (mapcar (lambda (f) (plist-get f :name)) (jetpacs-source-fields "glasspane.org"))
  "Field-name strings the \"glasspane.org\" source declares, for lint.")

(defconst glasspane-source-test--spec
  '(:source "glasspane.org"
    :params ((query . "todo:TODO"))
    :layout "list"
    :template ((t . "card")
               (children . [((t . "column")
                             (children . [((t . "text")
                                           (text . ((bind . "headline") (as . "string")))
                                           (style . "title"))
                                          ((t . "text")
                                           (text . ((bind . "scheduled") (as . "date-label")))
                                           (style . "caption"))]))])
               (on_tap . ((action . "heading.tap")
                          (args . ((bind . "ref"))))))
    :empty-state (:icon "task_alt" :title "No tasks")
    :chrome (:kind "nav" :title "Results" :back "files"))
  "A `:spec' bound to \"glasspane.org\" for the lint acceptance test.")

(ert-deftest glasspane-source-lint-accepts-bound-spec ()
  "`jetpacs-lint-view-spec' accepts a spec whose template binds declared fields."
  (should (null (jetpacs-lint-view-spec glasspane-source-test--spec
                                        glasspane-source-test--fields))))

(ert-deftest glasspane-source-lint-rejects-undeclared-field ()
  "A placeholder binding a field the source does not declare is a lint error."
  (let ((spec (copy-tree glasspane-source-test--spec)))
    (setf (plist-get spec :template)
          '((t . "text") (text . ((bind . "nonesuch") (as . "string")))))
    (should (jetpacs-lint-view-spec spec glasspane-source-test--fields))))

(provide 'glasspane-source-test)
;;; glasspane-source-test.el ends here
