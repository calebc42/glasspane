;;; glasspane-reader-layout-test.el --- Reader presentation tests -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))
;;; Commentary:
;; Presentation and action checks over explicit reader data.
;;; Code:
(require 'ert)
(require 'glasspane)
(require 'glasspane-org-reader)
(require 'jetpacs-chrome)

(ert-deftest glasspane-reader-layout-source-block-is-fontified-with-play ()
  "Code cards retain Emacs colors and group results under a folding header."
  (with-temp-buffer
    (insert "* Lab\nBefore.\n#+NAME: double\n#+begin_src emacs-lisp :var n=4\n(defun double (n)\n  (* 2 n))\n#+end_src\n\n#+RESULTS: double\n: 8\nAfter.\n")
    (org-mode)
    (font-lock-ensure)
    (goto-char 1)
    (search-forward "defun")
    (put-text-property (- (point) 5) (point) 'face '(:foreground "#123456" :weight bold))
    (let* ((source (buffer-string))
           (jetpacs-buffer-exposed (make-hash-table :test #'equal))
           (nodes (glasspane-org-reader--text-nodes source 1))
           (cards (glasspane-reader-layout--nodes-of-type nodes "card"))
           (buttons (glasspane-reader-layout--nodes-of-type nodes "icon_button"))
           (json (jetpacs-node->canonical-json (apply #'jetpacs-column nodes)))
           (args (plist-get (plist-get (car buttons) :on_tap) :args)))
      (should (= (length cards) 1))
      (should (equal (plist-get (car cards) :variant) "outlined"))
      (should (equal (plist-get (car buttons) :icon) "play_arrow"))
      (should (equal (plist-get (plist-get (car buttons) :on_tap) :action)
                     "jetpacs.org.execute-src-block"))
      (should (= (plist-get args :tick) (buffer-chars-modified-tick)))
      (should (jetpacs-buffer-exposed-p (buffer-name) (plist-get args :pos)
                                       "jetpacs.org.execute-src-block"))
      (dolist (text '("#123456" "double" ":var n=4" "Results" "After."))
        (should (string-search text json)))
      (should-not (string-search "#+begin_src" json))
      (should-not (string-search "#+RESULTS" json))
      (let* ((fold (car (glasspane-reader-layout--nodes-of-type cards "collapsible")))
             (body (jetpacs-node->canonical-json (aref (plist-get fold :children) 0))))
        (should (string-search "Results" body))
        (should (string-search "8" body))
        (should-not (string-search "After." body)))
      (should (equal json (jetpacs-node->canonical-json
                          (apply #'jetpacs-column
                                 (glasspane-org-reader--text-nodes source 1)))))
      (let ((jetpacs-buffer-budget (cons 0 10000))
            (jetpacs-buffer-exposed (make-hash-table :test #'equal)))
        (let ((fallback (glasspane-org-reader--text-nodes source 1)))
          (should-not (glasspane-reader-layout--nodes-of-type fallback "card"))
          (should-not (jetpacs-buffer-exposed-p (buffer-name) (plist-get args :pos)
                                               "jetpacs.org.execute-src-block"))))
      (should (equal-including-properties source (buffer-string))))))

(defun glasspane-reader-layout--with-source-file (fn)
  "Call FN with a temporary Org FILE and live source buffer."
  (let* ((root (make-temp-file "glasspane-source" t))
         (file (expand-file-name "code.org" root))
         (ebp-org-roots (list root))
         (org-babel-load-languages '((emacs-lisp . t) (python . t) (shell . nil)))
         (glasspane-org-reader--source-edit nil)
         (jetpacs-buffer-exposed (make-hash-table :test #'equal))
         buffer)
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Lab\nBefore.\n#+NAME: sample\n#+begin_src emacs-lisp -n :results value\n(+ 2 2)\n#+end_src\n\n#+RESULTS: sample\n: 4\nAfter.\n"))
          (setq buffer (find-file-noselect file))
          (with-current-buffer buffer
            (org-mode)
            (cl-letf (((symbol-function 'jetpacs-buffer-defer-refresh) #'ignore)
                      ((symbol-function 'jetpacs-shell-notify) #'ignore))
              (funcall fn file))))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-directory root t))))

(defun glasspane-reader-layout--source-render ()
  "Render the current source with fresh document IDs and explicit scope."
  (let ((jetpacs-node-id-claims (make-hash-table :test #'equal))
        (glasspane-org-reader--source-scope "test-source"))
    (glasspane-org-reader--text-nodes (buffer-string) (point-min))))

(defun glasspane-reader-layout--source-action (tree action)
  "Find the tap descriptor naming ACTION in TREE."
  (cl-loop for type in '("button" "icon_button")
           thereis (cl-loop for node in (glasspane-reader-layout--nodes-of-type tree type)
                            for tap = (plist-get node :on_tap)
                            when (equal action (plist-get tap :action)) return tap)))

(defun glasspane-reader-layout--source-open ()
  "Open the current buffer's source card using its emitted action."
  (let ((action (glasspane-reader-layout--source-action
                 (glasspane-reader-layout--source-render) "glasspane.source.edit")))
    (glasspane-org-reader--on-source-edit (plist-get action :args) '(:surface "app:glasspane"))))

(defun glasspane-reader-layout--source-save (text language)
  "Submit TEXT and LANGUAGE through the editor's actual captured fields."
  (let* ((action (glasspane-reader-layout--source-action
                  (glasspane-reader-layout--source-render) "glasspane.source.save"))
         (args (plist-get action :args)))
    (glasspane-org-reader--on-source-save
     args (list :surface "app:glasspane" :fields
                (list (intern (concat ":" (plist-get args :field))) text
                      (intern (concat ":" (plist-get args :language-field))) language)))))

(ert-deftest glasspane-reader-layout-inline-source-language-save ()
  "Native drafts are deterministic and save body/language without losing Org metadata."
  (glasspane-reader-layout--with-source-file
   (lambda (file)
     (let ((original (buffer-string)))
       (should (eq (glasspane-reader-layout--source-open) 'accepted))
       (should (eq (glasspane-reader-layout--source-open) 'rejected))
       (let* ((nodes (glasspane-reader-layout--source-render))
              (dropdown (car (glasspane-reader-layout--nodes-of-type nodes "dropdown")))
              (input (car (glasspane-reader-layout--nodes-of-type nodes "text_input"))))
         (should (equal (plist-get dropdown :value) "emacs-lisp"))
         (should (string-search "python" (jetpacs-node->canonical-json dropdown)))
         (should (equal (plist-get input :value) "(+ 2 2)\n"))
         (should-not (glasspane-reader-layout--source-action nodes "jetpacs.org.execute-src-block"))
         (should (equal nodes (glasspane-reader-layout--source-render)))
         (should (equal original (buffer-string))))
       (should (eq (glasspane-reader-layout--source-save "print(4)" "python") 'accepted))
       (should-not glasspane-org-reader--source-edit)
       (should-not (buffer-modified-p))
       (should (equal (buffer-string)
                      "* Lab\nBefore.\n#+NAME: sample\n#+begin_src python -n :results value\nprint(4)\n#+end_src\n\n#+RESULTS: sample\n: 4\nAfter.\n"))
       (should (equal (buffer-string)
                      (with-temp-buffer (insert-file-contents file) (buffer-string))))))))

(ert-deftest glasspane-reader-layout-inline-source-cancel-and-invalid ()
  "Cancel resets input identity; invalid fields cannot change source or language."
  (glasspane-reader-layout--with-source-file
   (lambda (_file)
     (let ((original (buffer-string)))
       (should (eq (glasspane-reader-layout--source-open) 'accepted))
       (let* ((id (plist-get glasspane-org-reader--source-edit :id))
              (cancel (glasspane-reader-layout--source-action
                       (glasspane-reader-layout--source-render) "glasspane.source.cancel")))
         (should (eq (glasspane-org-reader--on-source-cancel
                      (plist-get cancel :args) '(:surface "app:glasspane")) 'accepted))
         (should (eq (glasspane-reader-layout--source-open) 'accepted))
         (should-not (equal id (plist-get glasspane-org-reader--source-edit :id))))
       (should (eq (glasspane-reader-layout--source-save "#+END_SRC\n* Injected" "python") 'rejected))
       (should (eq (glasspane-reader-layout--source-save "print(4)" "python :var evil=1") 'rejected))
       (should-not (glasspane-org-reader--source-field '(:invalid . "bad") "invalid"))
       (should (equal original (buffer-string)))))))

(ert-deftest glasspane-reader-layout-inline-source-rejects-stale-and-failed-writes ()
  "Source and disk freshness guards reject lost updates and roll back failed saves."
  (dolist (failure '(buffer disk write))
    (glasspane-reader-layout--with-source-file
     (lambda (file)
       (should (eq (glasspane-reader-layout--source-open) 'accepted))
       (pcase failure
         ('buffer (goto-char (point-max)) (insert "New local text.\n"))
         ('disk (with-temp-file file (insert "* External replacement\n"))))
       (let ((before (buffer-string))
             (disk (with-temp-buffer (insert-file-contents file) (buffer-string))))
         (if (eq failure 'write)
             (cl-letf (((symbol-function 'glasspane-org-save-and-invalidate)
                        (lambda (&rest _) (error "Write refused"))))
               (should (eq (glasspane-reader-layout--source-save "print(4)" "python") 'rejected)))
           (should (eq (glasspane-reader-layout--source-save "print(4)" "python") 'stale)))
         (should (equal before (buffer-string)))
         (should (equal disk (with-temp-buffer (insert-file-contents file) (buffer-string))))
         (should glasspane-org-reader--source-edit))))))

(ert-deftest glasspane-reader-layout-source-results-native-and-bounded ()
  "Adjacent tables/images belong to code; remote named results stay in place."
  (with-temp-buffer
    (insert "* Lab\n#+begin_src python\n1\n#+end_src\n\n#+RESULTS:\n| Count |\n|-------|\n| 1 |\n\n#+begin_src python\n2\n#+end_src\n\n#+RESULTS:\n[[https://example.org/result.png]]\n\n#+NAME: distant\n#+begin_src python\n3\n#+end_src\n\nIntervening prose.\n\n#+RESULTS: distant\n: 3\n")
    (org-mode)
    (let* ((nodes (glasspane-reader-layout--source-render))
           (cards (glasspane-reader-layout--nodes-of-type nodes "card")))
      (should (= (length cards) 3))
      (should (= (length (glasspane-reader-layout--nodes-of-type (nth 0 cards) "table")) 1))
      (should (= (length (glasspane-reader-layout--nodes-of-type (nth 1 cards) "image")) 1))
      (should-not (string-search "Results" (jetpacs-node->canonical-json (nth 2 cards))))
      (should (string-search "#+RESULTS: distant" (jetpacs-node->canonical-json (apply #'jetpacs-column nodes)))))))

(ert-deftest glasspane-reader-layout-call-card-is-pure ()
  "Call cards expose literal arguments and their own results without resolving code."
  (with-temp-buffer
    (insert "* Calls\n#+NAME: named-call\n#+call: double[:var offset=1](n=(+ 2 3), text=\"a,b\") :results value\n\n#+RESULTS: named-call\n: 10\n\nAfter.\n#+begin_example\n#+call: example(n=5)\n#+end_example\n")
    (org-mode)
    (let ((before (buffer-string))
          (jetpacs-buffer-exposed (make-hash-table :test #'equal)))
      (cl-letf (((symbol-function 'org-babel-lob-get-info) (lambda (&rest _) (ert-fail "Builder resolved a call")))
                ((symbol-function 'org-babel-lob-execute-maybe) (lambda () (ert-fail "Builder executed a call"))))
        (let* ((nodes (glasspane-reader-layout--source-render))
               (cards (glasspane-reader-layout--nodes-of-type nodes "card"))
               (json (jetpacs-node->canonical-json (car cards)))
               (run (glasspane-reader-layout--source-action nodes "glasspane.call.execute")))
          (should (= (length cards) 1))
          (dolist (text '("Call" "double" "(+ 2 3)" "a,b" "Block options" ":var offset=1" "Call options" ":results value" "named-call" "Results" "10"))
            (should (string-search text json)))
          (should-not (string-search "After." json))
          (should-not (string-search "#+call:" json))
          (should (integerp (plist-get (plist-get run :args) :tick)))
          (should (equal nodes (glasspane-reader-layout--source-render)))
          (should (equal before (buffer-string)))))
      (let ((jetpacs-buffer-budget (cons 0 0))
            (jetpacs-buffer-exposed (make-hash-table :test #'equal)))
        (should-not (glasspane-reader-layout--source-action
                     (glasspane-reader-layout--source-render) "glasspane.call.execute")))
      (cl-letf (((symbol-function 'jetpacs-node-advertised-p) (lambda (_type) nil)))
        (let ((nodes (glasspane-reader-layout--source-render)))
          (should-not (glasspane-reader-layout--nodes-of-type nodes "card"))
          (should (string-search "#+call: double" (plist-get (car nodes) :text))))))))

(ert-deftest glasspane-reader-layout-call-results-do-not-activate-calls ()
  "Calls in source, example and result blocks never acquire Play actions."
  (with-temp-buffer
    (insert "* Calls\n#+begin_src text\n#+call: literal()\n#+end_src\n\n#+call: real()\n\n#+RESULTS:\n#+begin_example\n#+call: output()\n#+end_example\n")
    (org-mode)
    (let* ((nodes (glasspane-reader-layout--source-render))
           (buttons (glasspane-reader-layout--nodes-of-type nodes "icon_button")))
      (should (= 1 (cl-count-if
                    (lambda (button) (equal (plist-get (plist-get button :on_tap) :action)
                                            "glasspane.call.execute")) buttons)))
      (should (string-search "No arguments" (jetpacs-node->canonical-json (apply #'jetpacs-column nodes)))))))

(defun glasspane-reader-layout--call-fixture ()
  "Replace the temporary test file with a named block and a call to it."
  (erase-buffer)
  (insert "* Calls\n#+NAME: double\n#+begin_src emacs-lisp :var n=4 :results value\n(* 2 n)\n#+end_src\n\n#+RESULTS: double\n: 8\n\n#+call: double(n=5)\n")
  (save-buffer))

(defun glasspane-reader-layout--call-args ()
  "Return the current test buffer's rendered Babel call arguments."
  (plist-get (glasspane-reader-layout--source-action
              (glasspane-reader-layout--source-render) "glasspane.call.execute") :args))

(ert-deftest glasspane-reader-layout-call-executes-and-saves-results ()
  "A real Babel call uses its argument override and durably saves separate results."
  (glasspane-reader-layout--with-source-file
   (lambda (file)
     (glasspane-reader-layout--call-fixture)
     (let ((args (glasspane-reader-layout--call-args)))
       (should (eq (glasspane-org-reader--on-call-execute args '(:surface "app:glasspane")) 'accepted))
       (should (string-search "#+RESULTS: double\n: 8" (buffer-string)))
       (should (string-search "#+call: double(n=5)\n\n#+RESULTS:\n: 10" (buffer-string)))
       (should-not (buffer-modified-p))
       (should (equal (buffer-string) (with-temp-buffer (insert-file-contents file) (buffer-string))))
       (should (eq (glasspane-org-reader--on-call-execute args '(:surface "app:glasspane")) 'stale)))
     (let* ((nodes (glasspane-reader-layout--source-render))
            (calls (cl-remove-if-not
                    (lambda (card) (glasspane-reader-layout--source-action card "glasspane.call.execute"))
                    (glasspane-reader-layout--nodes-of-type nodes "card"))))
       (should (= (length calls) 1))
       (should (string-search "Results" (jetpacs-node->canonical-json (car calls))))))))

(ert-deftest glasspane-reader-layout-call-rejects-stale-and-failed-writes ()
  "Stale calls never execute, and failed saves restore the calling buffer."
  (dolist (failure '(buffer disk exposure write missing))
    (glasspane-reader-layout--with-source-file
     (lambda (file)
       (glasspane-reader-layout--call-fixture)
       (when (eq failure 'missing)
         (goto-char (point-max)) (search-backward "double(n=5)")
         (replace-match "missing(n=5)" t t) (save-buffer))
       (let ((args (glasspane-reader-layout--call-args)))
         (pcase failure
           ('buffer (goto-char (point-max)) (insert "Changed.\n"))
           ('disk (with-temp-file file (insert "* External edit\n")))
           ('exposure (clrhash jetpacs-buffer-exposed)))
         (let ((before (buffer-string))
               (disk (with-temp-buffer (insert-file-contents file) (buffer-string))))
           (pcase failure
             ('write
              (cl-letf (((symbol-function 'glasspane-org-save-and-invalidate)
                         (lambda (&rest _) (error "Write refused"))))
                (should (eq (glasspane-org-reader--on-call-execute args '(:surface "app:glasspane")) 'rejected))))
             ('missing (should (eq (glasspane-org-reader--on-call-execute args '(:surface "app:glasspane")) 'rejected)))
             (_ (cl-letf (((symbol-function 'org-babel-lob-execute-maybe)
                           (lambda () (ert-fail "Stale call executed"))))
                  (should (eq (glasspane-org-reader--on-call-execute args '(:surface "app:glasspane"))
                              (if (eq failure 'exposure) 'rejected 'stale))))))
           (should (equal before (buffer-string)))
           (should (equal disk (with-temp-buffer (insert-file-contents file) (buffer-string))))))))))

(defun glasspane-reader-layout--call-open ()
  "Open the call editor using its emitted Edit descriptor."
  (glasspane-org-reader--on-call-edit
   (plist-get (glasspane-reader-layout--source-action
               (glasspane-reader-layout--source-render) "glasspane.call.edit") :args)
   '(:surface "app:glasspane")))

(defun glasspane-reader-layout--call-save (value)
  "Save VALUE using the argument editor's emitted field identity."
  (let* ((action (glasspane-reader-layout--source-action
                  (glasspane-reader-layout--source-render) "glasspane.call.save"))
         (args (plist-get action :args)))
    (glasspane-org-reader--on-call-save
     args (list :surface "app:glasspane" :fields
                (list (intern (concat ":" (plist-get args :field))) value)))))

(ert-deftest glasspane-reader-layout-call-editor-save-preserves-syntax ()
  "Argument edits preserve surrounding syntax, metadata and results without evaluation."
  (dolist (value '("n=7" "n=(+ 2 3), text=\"a,b\"" "" "  "))
    (glasspane-reader-layout--with-source-file
     (lambda (file)
       (erase-buffer)
       (insert "* Calls\n#+NAME: saved-call\n  #+CaLl: double[:var offset=1](n=5)   :results value\n\n#+RESULTS: saved-call\n: 10\nAfter.\n")
       (save-buffer)
       (let ((before (buffer-string)))
         (should (eq (glasspane-reader-layout--call-open) 'accepted))
         (let* ((nodes (glasspane-reader-layout--source-render))
                (input (car (glasspane-reader-layout--nodes-of-type nodes "text_input"))))
           (should (equal (plist-get input :value) "n=5"))
           (should (equal nodes (glasspane-reader-layout--source-render)))
           (should-not (glasspane-reader-layout--source-action nodes "glasspane.call.execute")))
         (cl-letf (((symbol-function 'org-babel-lob-get-info) (lambda (&rest _) (ert-fail "Save evaluated arguments")))
                   ((symbol-function 'org-babel-lob-execute-maybe) (lambda () (ert-fail "Save executed call"))))
           (should (eq (glasspane-reader-layout--call-save value) 'accepted)))
         (should (equal (buffer-string) (string-replace "(n=5)" (concat "(" value ")") before)))
         (should (equal (buffer-string) (with-temp-buffer (insert-file-contents file) (buffer-string))))
         (should-not glasspane-org-reader--source-edit))))))

(ert-deftest glasspane-reader-layout-call-editor-cancel-and-invalid ()
  "Cancel discards drafts; malformed values cannot escape the argument field."
  (glasspane-reader-layout--with-source-file
   (lambda (_file)
     (glasspane-reader-layout--call-fixture)
     (let ((before (buffer-string)))
       (should (eq (glasspane-reader-layout--call-open) 'accepted))
       (should (eq (glasspane-reader-layout--source-open) 'rejected))
       (dolist (value '("n=5) :results silent (" "n=5\n* Heading" "n=(+ 2 3"))
         (should (eq (glasspane-reader-layout--call-save value) 'rejected)))
       (let* ((id (plist-get glasspane-org-reader--source-edit :id))
              (cancel (glasspane-reader-layout--source-action
                       (glasspane-reader-layout--source-render) "glasspane.call.cancel")))
         (should (eq (glasspane-org-reader--on-source-cancel
                      (plist-get cancel :args) '(:surface "app:glasspane")) 'accepted))
         (should (eq (glasspane-reader-layout--call-open) 'accepted))
         (should-not (equal id (plist-get glasspane-org-reader--source-edit :id))))
       (should (equal before (buffer-string)))))))

(ert-deftest glasspane-reader-layout-call-editor-rejects-stale-and-failed-writes ()
  "Argument Save rejects source/disk drift and rolls back a failed write."
  (dolist (failure '(buffer disk write))
    (glasspane-reader-layout--with-source-file
     (lambda (file)
       (glasspane-reader-layout--call-fixture)
       (should (eq (glasspane-reader-layout--call-open) 'accepted))
       (pcase failure
         ('buffer (goto-char (point-max)) (insert "New local text.\n"))
         ('disk (with-temp-file file (insert "* External replacement\n"))))
       (let ((before (buffer-string))
             (disk (with-temp-buffer (insert-file-contents file) (buffer-string))))
         (if (eq failure 'write)
             (cl-letf (((symbol-function 'glasspane-org-save-and-invalidate)
                        (lambda (&rest _) (error "Write refused"))))
               (should (eq (glasspane-reader-layout--call-save "n=7") 'rejected)))
           (should (eq (glasspane-reader-layout--call-save "n=7") 'stale)))
         (should (equal before (buffer-string)))
         (should (equal disk (with-temp-buffer (insert-file-contents file) (buffer-string))))
         (should glasspane-org-reader--source-edit))))))

(ert-deftest glasspane-reader-layout-emphasis-hides-markers-and-keeps-styles ()
  "All six emphasis forms hide markers; nesting combines supported native styles."
  (with-temp-buffer
    (insert "A *bold /nested/*, /italic/, _underline_, +retired+, ~code~, and =verbatim= end.\n")
    (org-mode)
    (let* ((before (buffer-string))
           (node (glasspane-org-reader--prose-node before))
           (spans (append (plist-get node :spans) nil))
           (plain (mapconcat (lambda (span) (plist-get span :text)) spans "")))
      (should (equal plain "A bold nested, italic, underline, retired, code, and verbatim end.\n"))
      (dolist (entry '(("bold " :font_weight "bold") ("nested" :italic t)
                       ("nested" :font_weight "bold") ("italic" :italic t)
                       ("underline" :underline t) ("code" :mono t) ("verbatim" :mono t)
                       ("code" :color "secondary") ("verbatim" :color "secondary")
                       ("code" :bg "#80808024") ("verbatim" :bg "#80808024")))
        (let ((span (cl-find (car entry) spans :key (lambda (item) (plist-get item :text)) :test #'equal)))
          (should span)
          (should (equal (plist-get span (cadr entry)) (caddr entry)))))
      (should (equal node (glasspane-org-reader--prose-node before)))
      (should (equal-including-properties before (buffer-string))))))

(ert-deftest glasspane-reader-layout-emphasis-preserves-literal-contexts ()
  "Org owns boundaries: code, examples, metadata, URLs and unmatched markers stay literal."
  (with-temp-buffer
    (insert "*bold* and ~*literal*~.\n\n#+begin_src text\n*source* /source/\n#+end_src\n\n#+begin_example\n*example* =example=\n#+end_example\n\n: *fixed*\n\n#+PROPERTY: MARK *metadata*\n\nhttps://example.org/a/b and snake_case and 2*3 and *unclosed\n")
    (org-mode)
    (let* ((text (buffer-string))
           (node (glasspane-org-reader--prose-node text))
           (plain (mapconcat (lambda (span) (plist-get span :text)) (plist-get node :spans) "")))
      (should (string-prefix-p "bold and *literal*." plain))
      (dolist (literal '("*source* /source/" "*example* =example=" ": *fixed*"
                         "*metadata*" "https://example.org/a/b" "snake_case" "2*3" "*unclosed"))
        (should (string-search literal plain)))
      (let ((jetpacs-buffer-budget (cons 0 10000)))
        (should (equal text (plist-get (glasspane-org-reader--prose-node text) :text))))
      (cl-letf (((symbol-function 'jetpacs-node-advertised-p) (lambda (_type) nil)))
        (should (equal text (plist-get (glasspane-org-reader--prose-node text) :text)))))))

(ert-deftest glasspane-reader-layout-emphasis-in-headings-and-checkboxes ()
  "Heading and checkbox labels hide markup without changing TODO or gesture descriptors."
  (with-temp-buffer
    (insert "* TODO A /title/\n- [ ] A *task*\n")
    (org-mode)
    (let* ((heading (glasspane-org-reader--heading-header '(:title "A /title/" :todo "TODO")))
           (heading-spans (plist-get (car (glasspane-reader-layout--nodes-of-type heading "rich_text")) :spans))
           (heading-text (mapconcat (lambda (span) (plist-get span :text)) heading-spans "")))
      (should (string-search "TODO" heading-text))
      (should (string-search "A title" heading-text))
      (should-not (string-search "/title/" heading-text))
      (goto-char (point-min)) (forward-line)
      (let* ((node (glasspane-org-reader--checkbox-node (glasspane-org-reader--checkbox-record (point))))
             (label (car (glasspane-reader-layout--nodes-of-type node "rich_text"))))
        (should (equal "A task" (mapconcat (lambda (span) (plist-get span :text)) (plist-get label :spans) "")))
        (should (string-search "glasspane.checkbox" (jetpacs-node->canonical-json node)))))))

(defun glasspane-reader-layout--footnote-actions (nodes)
  "Collect footnote link descriptors in NODES in presentation order."
  (cl-loop for node in (glasspane-reader-layout--nodes-of-type nodes "rich_text")
           append (cl-loop for span across (vconcat (plist-get node :spans))
                           for tap = (plist-get span :on_tap)
                           when (equal (plist-get tap :action) "glasspane.footnote.open")
                           collect tap)))

(ert-deftest glasspane-reader-layout-footnotes-link-and-hide-definitions ()
  "Real references become links; literal examples and unrelated headings survive."
  (glasspane-reader-layout--with-source-file
   (lambda (file)
     (erase-buffer)
     (insert "* Lab\nA *bold* note[fn:coverage], again[fn:coverage], inline[fn:n:Named /note/], anonymous[fn::Anon].\n\n#+begin_example\nLiteral[fn:coverage]\n#+end_example\n\n* Footnotes\n[fn:coverage] Definition only.\n\n** Nested\nHidden too.\n* After\nVisible.\n")
     (let* ((before (buffer-string))
            (nodes (glasspane-reader-layout--source-render))
            (actions (glasspane-reader-layout--footnote-actions nodes)))
       (should (= (length actions) 4))
       (dolist (action actions)
         (let ((pos (plist-get (plist-get action :args) :pos)))
           (should (jetpacs-buffer-exposed-p (buffer-name) pos "glasspane.footnote.open"))
           (should (glasspane-org-reader--footnote-record pos))))
       (should (equal nodes (glasspane-reader-layout--source-render)))
       (let ((json (jetpacs-node->canonical-json (apply #'jetpacs-column nodes))))
         (should (string-search "Literal[fn:coverage]" json))
         (should-not (string-search "Definition only." json)))
       (cl-letf (((symbol-function 'glasspane-org-reader--mint)
                  (lambda (&rest _) (make-hash-table :test #'eql))))
         (let* ((tree (glasspane-org-reader-file file))
                (json (jetpacs-node->canonical-json (apply #'jetpacs-column tree))))
           (should (string-search "Visible." json))
           (should-not (string-search "Footnotes" json))
           (should-not (string-search "Hidden too." json))))
       (should (equal before (buffer-string)))))))

(ert-deftest glasspane-reader-layout-footnote-dialog-saves-normal-and-inline ()
  "Dialog Save durably updates exactly one definition; Cancel leaves source alone."
  (dolist (source '("* Lab\nRead[fn:a].\n* Footnotes\n[fn:a] Old *note*\n\n[fn:b] Other.\n"
                    "* Lab\nRead[fn:a:Old *note*] and[fn:a].\n"
                    "* Lab\nRead[fn:a], defined here[fn:a:Old *note*].\n"
                    "* Lab\nRead[fn::Old *note*].\n"))
    (glasspane-reader-layout--with-source-file
     (lambda (file)
       (erase-buffer) (insert source) (save-buffer)
       (let ((glasspane-org-reader--footnote-dialog nil) shown callback)
         (cl-letf (((symbol-function 'jetpacs-client) (lambda () 'client))
                   ((symbol-function 'jetpacs-node-advertised-p) (lambda (&rest _) t))
                   ((symbol-function 'jetpacs-node-member-advertised-p) (lambda (&rest _) t))
                   ((symbol-function 'jetpacs-granted-p) (lambda (&rest _) t))
                   ((symbol-function 'jetpacs-flow-continue) #'funcall)
                   ((symbol-function 'ebp-client-dialog-show)
                    (lambda (_client _id spec &rest opts)
                      (setq shown spec callback (plist-get opts :callback)) "request"))
                   ((symbol-function 'ebp-client-abandon) (lambda (&rest _) nil)))
           (let* ((action (car (glasspane-reader-layout--footnote-actions
                               (glasspane-reader-layout--source-render))))
                  (args (plist-get action :args)))
             (should (eq (glasspane-org-reader--on-footnote-open args '(:surface "app:glasspane")) 'accepted))
             (should-not (glasspane-reader-layout--nodes-of-type shown "text_input"))
             (funcall callback "dismissed" nil nil)
             (should-not glasspane-org-reader--footnote-dialog)
             (should (equal source (buffer-string)))
             (should (eq (glasspane-org-reader--on-footnote-open args '(:surface "app:glasspane")) 'accepted))
             (let ((id (plist-get glasspane-org-reader--footnote-dialog :id))
                   (old-callback callback))
               (should (eq (glasspane-org-reader--on-footnote-edit
                            (list :session id) (list :dialog_id id)) 'accepted))
               (should-not (equal id (plist-get glasspane-org-reader--footnote-dialog :id)))
               (funcall old-callback "dismissed" nil nil)
               (should glasspane-org-reader--footnote-dialog))
             (should (equal (plist-get (car (glasspane-reader-layout--nodes-of-type shown "text_input")) :value)
                            "Old *note*"))
             (let ((id (plist-get glasspane-org-reader--footnote-dialog :id)))
               (should (eq (glasspane-org-reader--on-footnote-save
                            (list :session id)
                            (list :dialog_id id :fields '(:footnote-text "New /note/"))) 'accepted)))
             (should-not glasspane-org-reader--footnote-dialog)
             (let ((expected (replace-regexp-in-string "Old \\*note\\*" "New /note/" source t t)))
               (should (equal expected (buffer-string)))
               (should (equal expected (with-temp-buffer (insert-file-contents file) (buffer-string))))))))))))

(ert-deftest glasspane-reader-layout-footnote-save-rejects-stale-invalid-and-failed-write ()
  "Wrong dialogs, invalid Org, source/disk drift and write errors cannot clobber notes."
  (dolist (failure '(wrong-dialog invalid source disk write))
    (glasspane-reader-layout--with-source-file
     (lambda (file)
       (erase-buffer) (insert "* Lab\nRead[fn:a].\n* Footnotes\n[fn:a] Original.\n") (save-buffer)
       (let* ((before (buffer-string))
              (action (car (glasspane-reader-layout--footnote-actions (glasspane-reader-layout--source-render))))
              (record (glasspane-org-reader--footnote-record (plist-get (plist-get action :args) :pos)))
              (glasspane-org-reader--footnote-dialog
               (append record '(:id "fn-test" :editing t :field "footnote-text" :request-id "req" :surface "app:glasspane"))))
         (pcase failure
           ('source (goto-char (point-max)) (insert "Changed elsewhere."))
           ('disk (with-temp-file file (insert "Changed on disk."))))
         (let ((after-drift (buffer-string)))
           (cl-letf (((symbol-function 'glasspane-org-save-and-invalidate)
                      (lambda (&rest _) (error "Simulated failed write"))))
             (should
              (eq (glasspane-org-reader--on-footnote-save
                   '(:session "fn-test")
                   (list :dialog_id (if (eq failure 'wrong-dialog) "other" "fn-test")
                         :fields (list :footnote-text
                                       (if (eq failure 'invalid) "Escape.\n* New heading\n" "New note."))))
                  (if (memq failure '(wrong-dialog source disk)) 'stale 'rejected))))
           (should (equal after-drift (buffer-string)))
           (should glasspane-org-reader--footnote-dialog)
           (unless (eq failure 'disk)
             (should (equal before (with-temp-buffer (insert-file-contents file) (buffer-string)))))))))))

(ert-deftest glasspane-reader-layout-export-cards-retain-faces-and-literal-code ()
  "Export cards carry prepared colors and unique folds without hiding or executing code."
  (with-temp-buffer
    (insert "#+begin_export html\n<aside>*literal* export</aside>\n#+end_export\n")
    (org-mode)
    (goto-char (point-min)) (search-forward "aside")
    (put-text-property (- (point) 5) (point) 'face '(:foreground "#123456"))
    (put-text-property (- (point) 5) (point) 'invisible t)
    (let* ((before (buffer-string))
           (nodes (glasspane-reader-layout--source-render))
           (card (car (glasspane-reader-layout--nodes-of-type nodes "card")))
           (fold (car (glasspane-reader-layout--nodes-of-type card "collapsible")))
           (code (car (glasspane-reader-layout--nodes-of-type card "rich_text")))
           (plain (mapconcat (lambda (span) (plist-get span :text)) (plist-get code :spans) "")))
      (should (equal (plist-get card :variant) "outlined"))
      (should (equal (plist-get (plist-get fold :header) :text) "HTML export"))
      (should (equal plain "<aside>*literal* export</aside>"))
      (should (string-search "#123456" (jetpacs-node->canonical-json code)))
      (should-not (glasspane-reader-layout--nodes-of-type card "icon_button"))
      (should (equal nodes (glasspane-reader-layout--source-render)))
      (let* ((jetpacs-node-id-claims (make-hash-table :test #'equal))
             (a (glasspane-org-reader--text-nodes before 1))
             (b (glasspane-org-reader--text-nodes before 1))
             (ids (jetpacs-collect-node-ids (vector a b) nil)))
        (should (= (length ids) 2))
        (should (= (length (delete-dups ids)) 2)))
      (should (equal-including-properties before (buffer-string))))))

(ert-deftest glasspane-reader-layout-special-blocks-have-named-folding-cards ()
  "Custom block names become unique folding titles without modifying Org text."
  (with-temp-buffer
    (insert "Before.\n#+begin_callout :icon info\nA *bold* point.\n#+end_callout\n\n#+begin_custom_name\nSecond.\n#+end_custom_name\n\n#+begin_callout\nThird.\n#+end_callout\n\nAfter.\n#+begin_unfinished\nKeep source.\n")
    (org-mode)
    (let* ((before (buffer-string))
           (nodes (glasspane-reader-layout--source-render))
           (cards (glasspane-reader-layout--nodes-of-type nodes "card"))
           (folds (glasspane-reader-layout--nodes-of-type nodes "collapsible"))
           (json (jetpacs-node->canonical-json (apply #'jetpacs-column nodes))))
      (should (= (length cards) 3))
      (dolist (card cards) (should (equal (plist-get card :variant) "outlined")))
      (should (equal (mapcar (lambda (fold) (plist-get (plist-get fold :header) :text)) folds)
                     '("callout" "custom_name" "callout")))
      (should (string-search "bold" json))
      (should-not (string-search "*bold*" json))
      (dolist (text '(":icon info" "Before." "Second." "Third." "After." "#+begin_unfinished"))
        (should (string-search text json)))
      (should-not (string-search "#+begin_callout" json))
      (should-not (string-search "#+end_custom_name" json))
      (should-not (glasspane-reader-layout--nodes-of-type nodes "icon_button"))
      (should (equal nodes (glasspane-reader-layout--source-render)))
      (let* ((jetpacs-node-id-claims (make-hash-table :test #'equal))
             (a (glasspane-org-reader--text-nodes before 1))
             (b (glasspane-org-reader--text-nodes before 1))
             (ids (jetpacs-collect-node-ids (vector a b) nil)))
        (should (= (length ids) 6))
        (should (= (length (delete-dups ids)) 6)))
      (let* ((jetpacs-buffer-budget (cons 0 0))
             (fallback (glasspane-reader-layout--source-render)))
        (should-not (glasspane-reader-layout--nodes-of-type fallback "card"))
        (should (string-search "#+begin_callout"
                               (jetpacs-node->canonical-json (apply #'jetpacs-column fallback)))))
      (should (equal-including-properties before (buffer-string))))))

(ert-deftest glasspane-reader-layout-fixed-width-preserves-literal-spacing ()
  "Fixed-width sections hide only Org prefixes and share the example presentation."
  (dolist (source '(":   *literal* [[link]]\n:\n: second\tcolumn  \n:\n\nAfter.\n"
                    ":   *literal* [[link]]\n:\n: second\tcolumn  \n:"
                    ":"))
    (with-temp-buffer
      (insert source) (org-mode) (goto-char (point-min))
      (let* ((value (if (equal source ":") "" "  *literal* [[link]]\n\nsecond\tcolumn  \n"))
             (nodes (glasspane-reader-layout--source-render))
             (box (cl-find glasspane-org-reader--literal-background
                           (glasspane-reader-layout--nodes-of-type nodes "box")
                           :key (lambda (node) (plist-get node :bg)) :test #'equal))
             (literal (car (glasspane-reader-layout--nodes-of-type box "text"))))
        (should box)
        (should (equal (plist-get literal :text) value))
        (should (equal (plist-get literal :style) "mono"))
        (should-not (plist-get literal :syntax))
        (should (equal nodes (glasspane-reader-layout--source-render)))
        (should (equal source (buffer-string)))
        (when (string-search "After." source)
          (should (string-search "After." (jetpacs-node->canonical-json (apply #'jetpacs-column nodes)))))
        (let ((jetpacs-buffer-budget (cons 0 0)))
          (let ((fallback (glasspane-reader-layout--source-render)))
            (should-not (glasspane-reader-layout--nodes-of-type fallback "box"))
            (should (cl-some (lambda (node) (equal (plist-get node :text) source))
                             (glasspane-reader-layout--nodes-of-type fallback "text")))))))))

(ert-deftest glasspane-reader-layout-prose-blocks-have-distinct-presentations ()
  "Quotes, poems, centered text, examples, comments and exports retain their contents."
  (with-temp-buffer
    (insert "Before.\n#+begin_quote\nA *quoted* thought.\n#+end_quote\n\n#+begin_verse\nFirst *line*\n\n  Second line\n#+end_verse\n\n#+begin_center\nCentered /text/\nShort\n#+end_center\n\n#+begin_example\n  *literal* [[link]]\n#+call: never()\n#+end_example\n\n#+begin_comment\nA *hidden* implementation note.\n#+end_comment\n\n# Standalone comment\n\n#+begin_export html\n<aside>*literal* export</aside>\n#+end_export\nAfter.\n")
    (org-mode)
    (let* ((before (buffer-string))
           (nodes (glasspane-reader-layout--source-render))
           (json (jetpacs-node->canonical-json (apply #'jetpacs-column nodes)))
           (boxes (glasspane-reader-layout--nodes-of-type nodes "box"))
           (columns (glasspane-reader-layout--nodes-of-type nodes "column"))
           (centers (cl-remove-if-not (lambda (node) (equal (plist-get node :align) "center")) columns))
           (texts (glasspane-reader-layout--nodes-of-type nodes "text")))
      (should (cl-some (lambda (box) (and (equal (plist-get box :bg) "secondary")
                                         (equal (plist-get (aref (plist-get box :children) 0) :pad) '(:start 3)))) boxes))
      (should (cl-some (lambda (box) (equal (plist-get box :bg) glasspane-org-reader--literal-background)) boxes))
      (should (= (length centers) 2))
      (let ((verse (car centers)))
        (should (= (length (plist-get verse :children)) 3))
        (dolist (node (glasspane-reader-layout--nodes-of-type verse "rich_text"))
          (mapc (lambda (span) (should (eq (plist-get span :italic) t))) (plist-get node :spans))))
      (should (cl-some (lambda (node) (and (string-search "*literal* [[link]]" (plist-get node :text))
                                          (equal (plist-get node :style) "mono")
                                          (not (plist-get node :syntax)))) texts))
      (dolist (comment '("A *hidden* implementation note." "Standalone comment"))
        (let ((node (cl-find comment texts :key (lambda (item) (plist-get item :text)) :test #'equal)))
          (should (equal (plist-get node :style) "caption"))
          (should (equal (plist-get node :color) "outline"))))
      (dolist (text '("HTML export" "<aside>*literal* export</aside>" "Before." "After." "  Second line"))
        (should (string-search text json)))
      (dolist (marker '("#+begin_quote" "#+end_quote" "#+begin_verse" "#+begin_center" "#+begin_example" "#+begin_comment" "#+begin_export"))
        (should-not (string-search marker json)))
      (should-not (glasspane-reader-layout--source-action nodes "glasspane.call.execute"))
      (should (equal nodes (glasspane-reader-layout--source-render)))
      (should (equal-including-properties before (buffer-string))))))

(ert-deftest glasspane-reader-layout-prose-blocks-handle-eof-and-empty ()
  "A final delimiter without newline and an empty block lose no neighboring text."
  (dolist (kind '("quote" "verse" "center" "example" "comment" "export html" "callout"))
    (with-temp-buffer
      (let* ((end-kind (car (split-string kind)))
             (source (format "Before.\n#+begin_%s\n#+end_%s\nMiddle.\n#+begin_%s\n  Last line\n#+end_%s"
                             kind end-kind kind end-kind)))
        (insert source) (org-mode)
        (let* ((nodes (glasspane-reader-layout--source-render))
               (json (jetpacs-node->canonical-json (apply #'jetpacs-column nodes))))
          (should (string-search "Before." json))
          (should (string-search "Middle." json))
          (should (string-search "  Last line" json))
          (should-not (string-search "#+begin_" json))
          (should (equal source (buffer-string))))))))

(ert-deftest glasspane-reader-layout-prose-blocks-preserve-unsupported-and-literal ()
  "Incomplete blocks and quoted source examples remain source, with bounded native fallback."
  (with-temp-buffer
    (insert "#+begin_example\n#+begin_quote\n*literal*\n#+end_quote\n#+end_example\n\n#+begin_details\nUnknown.\n#+end_details\n\n#+begin_quote\nUnclosed.\n")
    (org-mode)
    (let ((nodes (glasspane-reader-layout--source-render)))
      (should (cl-some (lambda (node) (equal (plist-get node :text) "#+begin_quote\n*literal*\n#+end_quote"))
                       (glasspane-reader-layout--nodes-of-type nodes "text")))
      (let ((json (jetpacs-node->canonical-json (apply #'jetpacs-column nodes))))
        (should (string-search "details" json))
        (should-not (string-search "#+begin_details" json))
        (should (string-search "#+begin_quote\\nUnclosed." json))))
    (let ((jetpacs-buffer-budget (cons 0 0)))
      (should-not (glasspane-reader-layout--nodes-of-type (glasspane-reader-layout--source-render) "box")))))

(ert-deftest glasspane-reader-layout-images-coexist-with-tables ()
  "The demo image and caption render without upgrading example/prose links."
  (with-temp-buffer
    (insert "* Lab\nBefore.\n\n#+CAPTION: Standalone remote image with alt text\n#+ATTR_ORG: :width 640\n[[https://picsum.photos/seed/glasspane-org/640/320.jpg]]\n\n| Feature | State |\n|---------+-------|\n| Images | ready |\n\n- [ ] Task\n\n[[https://example.org/second.png][Second picture]]\n\n[[https://example.org/prose.png]] followed by prose.\n\n#+begin_src text\n#+CAPTION: Example\n[[https://example.org/example.png]]\n#+end_src\nAfter.\n")
    (org-mode)
    (let* ((source (buffer-string))
           (jetpacs-buffer-exposed (make-hash-table :test #'equal))
           (nodes (glasspane-org-reader--text-nodes source 1))
           (images (glasspane-reader-layout--nodes-of-type nodes "image"))
           (json (jetpacs-node->canonical-json (apply #'jetpacs-column nodes))))
      (should (equal (mapcar (lambda (node) (plist-get node :url)) images)
                     '("https://picsum.photos/seed/glasspane-org/640/320.jpg"
                       "https://example.org/second.png")))
      (should (= (length (glasspane-reader-layout--nodes-of-type nodes "table")) 1))
      (should (= (length (glasspane-reader-layout--nodes-of-type nodes "checkbox")) 1))
      (dolist (text '("Before." "After." "Standalone remote image with alt text"
                      "[[https://example.org/prose.png]] followed by prose."
                      "[[https://example.org/example.png]]"))
        (should (string-search text json)))
      (should-not (string-search "#+ATTR_ORG" json))
      (should-not (string-search "#+CAPTION: Standalone" json))
      (should (equal json (jetpacs-node->canonical-json
                          (apply #'jetpacs-column
                                 (glasspane-org-reader--text-nodes source 1)))))
      (cl-letf (((symbol-function 'jetpacs-feature-advertised-p) (lambda (&rest _) nil)))
        (let* ((fallback (glasspane-org-reader--text-nodes source 1))
               (plain (jetpacs-node->canonical-json (apply #'jetpacs-column fallback))))
          (should-not (glasspane-reader-layout--nodes-of-type fallback "image"))
          (should (string-search "#+CAPTION: Standalone" plain))
          (should (string-search "[[https://picsum.photos" plain))))
      (should (equal source (buffer-string))))))

(ert-deftest glasspane-reader-layout-tables-preserve-surrounding-source ()
  "Tables coexist with checkboxes, formulas and literal block examples."
  (with-temp-buffer
    (insert "* Lab\nBefore.\n- [ ] Task\n#+NAME: matrix\n| <l18> | <r12> |\n| Feature | Count |\n|---------+-------|\n| Ready | 12 |\n#+TBLFM: $2=6+6\nAfter.\n#+begin_src text\n| Example | Source |\n#+end_src\n#+begin_example\n| Literal | Example |\n#+end_example\n\n| Next | Table |\n")
    (org-mode)
    (let* ((source (buffer-string))
           (jetpacs-buffer-exposed (make-hash-table :test #'equal))
           (nodes (glasspane-org-reader--text-nodes source 1))
           (tables (glasspane-reader-layout--nodes-of-type nodes "table"))
           (json (jetpacs-node->canonical-json (apply #'jetpacs-column nodes))))
      (should (= (length tables) 2))
      (should (= (length (glasspane-reader-layout--nodes-of-type nodes "checkbox")) 1))
      (should (equal (plist-get (car tables) :aligns) ["start" "end"]))
      (should (equal (mapcar (lambda (row) (plist-get row :kind))
                            (append (plist-get (car tables) :rows) nil))
                     '("header" "rule" "data")))
      (dolist (text '("Before." "After." "#+NAME: matrix" "#+TBLFM: $2=6+6"
                      "| Example | Source |" "| Literal | Example |"))
        (should (string-search text json)))
      (should-not (string-search "<l18>" json))
      (should (equal json (jetpacs-node->canonical-json
                          (apply #'jetpacs-column
                                 (glasspane-org-reader--text-nodes source 1)))))
      (let ((jetpacs-buffer-extra-budget '((:max_table_cells . 0))))
        (let ((fallback (glasspane-org-reader--text-nodes source 1)))
          (should-not (glasspane-reader-layout--nodes-of-type fallback "table"))
          (should (string-search "| Feature | Count |"
                                 (jetpacs-node->canonical-json
                                  (apply #'jetpacs-column fallback))))))
      (cl-letf (((symbol-function 'jetpacs-node-advertised-p)
                 (lambda (type) (equal type "table")))
                ((symbol-function 'jetpacs-node-member-advertised-p)
                 (lambda (type _member) (equal type "table"))))
        (let ((table-only (glasspane-org-reader--text-nodes source 1)))
          (should (= (length (glasspane-reader-layout--nodes-of-type table-only "table")) 2))
          (should-not (glasspane-reader-layout--nodes-of-type table-only "checkbox"))))
      (should (equal source (buffer-string))))))

(ert-deftest glasspane-reader-layout-nested-drill-has-unique-fold-ids ()
  "A retained file and nested detail views coexist without duplicate IDs."
  (let* ((vault (make-temp-file "glasspane-nested-drill" t))
         (file (expand-file-name "lab.org" vault))
         (ebp-org-roots (list vault))
         (jetpacs-buffer-exposed (make-hash-table :test #'equal)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Org feature lab\n- [ ] Parent task\n** Child\n- [-] Child task\n*** Grandchild\nBody\n** Sibling\nBody\n* Other\n"))
          ;; Token minting is outside this presentation identity check.
          (cl-letf (((symbol-function 'glasspane-org-reader--mint)
                     (lambda (&rest _) (make-hash-table :test #'eql))))
            (cl-labels
                ((render ()
                   (let* ((jetpacs-node-id-claims (make-hash-table :test #'equal))
                          (seen (make-hash-table :test #'equal))
                          (whole (apply #'jetpacs-column (glasspane-org-reader-file file)))
                          (whole-ids (jetpacs-collect-node-ids whole nil)))
                     (jetpacs-chrome--claim-screen-ids whole seen)
                     (let ((detail (apply #'jetpacs-column
                                          (glasspane-org-reader-subtree file 1))))
                       (should (= (length (glasspane-reader-layout--nodes-of-type
                                          detail "collapsible")) 3))
                       (jetpacs-chrome--claim-screen-ids detail seen)
                       (let* ((pos (with-current-buffer (find-file-noselect file)
                                     (save-excursion
                                       (goto-char 1) (search-forward "** Child")
                                       (line-beginning-position))))
                              (nested (apply #'jetpacs-column
                                             (glasspane-org-reader-subtree file pos))))
                         (jetpacs-chrome--claim-screen-ids nested seen)
                         ;; Later claims must not rename the retained file's folds.
                         (should (equal whole-ids (jetpacs-collect-node-ids whole nil)))
                         (jetpacs-node->canonical-json
                          (jetpacs-column whole detail nested)))))))
              (should (equal (render) (render))))))
      (when-let* ((buffer (find-buffer-visiting file))) (kill-buffer buffer))
      (delete-directory vault t))))

(defun glasspane-reader-layout--nodes-of-type (tree type)
  "Collect nodes of TYPE within the ordinary IR TREE."
  (let (nodes)
    (cl-labels ((walk (value)
                  (cond ((vectorp value) (mapc #'walk value))
                        ((consp value)
                         (when (equal (plist-get value :t) type)
                           (push value nodes))
                         (mapc #'walk value)))))
      (walk tree))
    (nreverse nodes)))

(ert-deftest glasspane-reader-layout-native-checkboxes-exclude-examples ()
  "Native checkbox states and gestures preserve nested lists and prose."
  (with-temp-buffer
    (insert "* Tasks\nIntro.\n- [ ] One\n  Continued text.\n  - [-] Nested\n1. [X] Numbered\n#+begin_src text\n- [ ] Example\n#+end_src\nAfter.\n")
    (org-mode)
    (let* ((jetpacs-buffer-exposed (make-hash-table :test #'equal))
           (source (buffer-string))
           (nodes (glasspane-org-reader--text-nodes source 1))
           (checks (glasspane-reader-layout--nodes-of-type nodes "checkbox"))
           (boxes (glasspane-reader-layout--nodes-of-type nodes "box"))
           (json (jetpacs-node->canonical-json (apply #'jetpacs-column nodes))))
      (should (equal (mapcar (lambda (node) (plist-get node :state)) checks)
                     '("off" "indeterminate" "on")))
      (should (= (length (delete-dups (mapcar (lambda (node) (plist-get node :id)) checks))) 3))
      (dolist (box boxes)
        (when (plist-get box :on_tap)
          (should (equal (plist-get (plist-get box :on_tap) :action) "glasspane.checkbox"))
          (should (equal (plist-get (plist-get (plist-get box :on_long_tap) :args) :state)
                         "indeterminate"))))
      (should (= (cl-count-if (lambda (box) (plist-get box :on_long_tap)) boxes) 6))
      (dolist (text '("Continued text." "1." "- [ ] Example" "After."))
        (should (string-search text json)))
      (should (equal json (jetpacs-node->canonical-json
                          (apply #'jetpacs-column
                                 (glasspane-org-reader--text-nodes source 1)))))
      ;; A retained file view and its opened heading share one document.
      (let* ((jetpacs-node-id-claims (make-hash-table :test #'equal))
             (file-nodes (glasspane-org-reader--text-nodes source 1))
             (heading-nodes (glasspane-org-reader--text-nodes source 1))
             (ids (jetpacs-collect-node-ids (vector file-nodes heading-nodes) nil)))
        (should (= (length ids) 8))
        (should (= (length (delete-dups ids)) 8)))
      (cl-letf (((symbol-function 'jetpacs-node-member-advertised-p) (lambda (&rest _) nil)))
        (let ((fallback (glasspane-org-reader--text-nodes source 1)))
          (should-not (glasspane-reader-layout--nodes-of-type fallback "checkbox"))
          (should (string-search "- [ ] One" (plist-get (car fallback) :text)))))
      (should (equal source (buffer-string))))))

(ert-deftest glasspane-reader-layout-checkbox-saves-and-rejects-stale-taps ()
  "Checkbox gestures save synchronously; stale or failed edits change no text."
  (let* ((root (make-temp-file "glasspane-checks" t))
         (file (expand-file-name "tasks.org" root))
         (ebp-org-roots (list root))
         (jetpacs-buffer-exposed (make-hash-table :test #'equal))
         buffer)
    (unwind-protect
        (progn
          (with-temp-file file (insert "* Tasks [0/2]\n- [ ] One\n- [ ] Two\n"))
          (setq buffer (find-file-noselect file))
          (with-current-buffer buffer
            (org-mode)
            (cl-labels ((args ()
                          (goto-char 1)
                          (search-forward "One")
                          (let ((node (glasspane-org-reader--checkbox-node
                                       (glasspane-org-reader--checkbox-record (point)))))
                            (plist-get (plist-get node :on_tap) :args)))
                        (tap (args)
                          (glasspane-org-reader--on-checkbox args '(:surface "app:glasspane")))
                        (disk () (with-temp-buffer (insert-file-contents file) (buffer-string))))
              (cl-letf (((symbol-function 'jetpacs-buffer-defer-refresh) #'ignore))
                (let ((tap-args (args)))
                  ;; An unrelated active region must not toggle the second item.
                  (set-mark (point-max))
                  (setq mark-active t)
                  (should (eq (tap tap-args) 'accepted)))
                (should (string-search "[1/2]" (disk)))
                (should (string-search "- [X] One" (disk)))
                (should (string-search "- [ ] Two" (disk)))
                (should-not (buffer-modified-p))
                (should (eq (tap (append (args) '(:state "indeterminate"))) 'accepted))
                (should (string-search "- [-] One" (disk)))
                (should (string-search "[0/2]" (disk)))
                (should (eq (tap (args)) 'accepted))
                (should (string-search "- [X] One" (disk)))
                (should (eq (tap (args)) 'accepted))
                (should (string-search "- [ ] One" (disk)))
                (let ((before (buffer-string)) (tap-args (args)))
                  (cl-letf (((symbol-function 'glasspane-org-save-and-invalidate)
                             (lambda (&rest _) (error "Write refused"))))
                    (should (eq (tap tap-args) 'rejected)))
                  (should (equal before (buffer-string)))
                  (should (equal before (disk))))
                (let ((tap-args (args)))
                  (goto-char (point-max))
                  (insert "Changed after render.\n")
                  (let ((changed (buffer-string)))
                    (should (eq (tap tap-args) 'stale))
                    (should (equal changed (buffer-string)))))))))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest glasspane-reader-layout-properties-render-local-name-value-rows ()
  "Property rows preserve exact values and order without displaying Org delimiters."
  (with-temp-buffer
    (insert "* Parent\n:PROPERTIES:\n:ID: parent-id\n:Effort: 30min\n:OWNER: Demo Person\n:CUSTOM_ID: local-anchor\n:EMPTY:\n:OWNER: Second owner\n:END:\n")
    (org-mode)
    (let* ((source (buffer-string))
           (drawer (car (jetpacs-org-render-heading-drawers 1)))
           (rows (glasspane-org-reader--property-nodes drawer))
           (labels (mapcar (lambda (row) (plist-get (aref (plist-get row :children) 0) :text)) rows))
           (values (mapcar (lambda (row) (plist-get (aref (plist-get row :children) 1) :text)) rows))
           (panel (glasspane-org-reader--drawer-node drawer))
           (column (aref (plist-get panel :children) 0))
           (header (aref (plist-get column :children) 0)))
      (should (equal labels '("ID" "Effort" "Owner" "Custom ID" "Empty" "Owner")))
      (should (equal values '("parent-id" "30min" "Demo Person" "local-anchor" "—" "Second owner")))
      (should (equal (plist-get header :arrange) "start"))
      (dolist (row rows)
        (let ((value (aref (plist-get row :children) 1)))
          (should (eq (plist-get value :selectable) t))
          (should-not (plist-get value :max_lines))))
      (should (equal (jetpacs-node->canonical-json panel)
                     (jetpacs-node->canonical-json (glasspane-org-reader--drawer-node drawer))))
      (should (equal source (buffer-string))))))

(ert-deftest glasspane-reader-layout-clock-entries-preserve-freeform-text ()
  "Completed and running clocks render without losing adjacent log text."
  (let* ((source "Before clock.\n  CLOCK: [2026-09-01 Tue 08:20]--[2026-09-01 Tue 08:34] =>  0:14\nAfter clock.\nCLOCK: [2026-09-01 Tue 23:50]--[2026-09-02 Wed 00:10] =>  0:20\nCLOCK: [2026-09-02 Wed 09:00]\n- Note taken on [2026-09-02 Wed 09:01]\n  Keep this note.\nCLOCK: malformed\n")
         (nodes (glasspane-org-reader--logbook-nodes source))
         (json (decode-coding-string
                (jetpacs-node->canonical-json (apply #'jetpacs-column nodes))
                'utf-8)))
    (should (equal (mapcar (lambda (node) (plist-get node :t)) nodes)
                   '("text" "row" "text" "row" "row" "text")))
    (dolist (text '("Before clock." "After clock." "Keep this note."
                    "CLOCK: malformed" "2026-09-01, 08:20 to 08:34"
                    "2026-09-01 23:50 to 2026-09-02 00:10"
                    "Duration · 0:14" "Running" "timer"))
      (should (string-search text json)))
    (should-not (string-search "CLOCK: [2026" json))
    (should (equal json (decode-coding-string
                        (jetpacs-node->canonical-json
                         (apply #'jetpacs-column
                                (glasspane-org-reader--logbook-nodes source)))
                        'utf-8)))))

(ert-deftest glasspane-reader-layout-inline-todo-uses-org-face ()
  "TODO and title share a line, honoring buffer-local keyword colors."
  (with-temp-buffer
    (org-mode)
    (setq-local org-todo-keyword-faces '(("NEXT" . (:foreground "#123456"))))
    (let* ((record '(:title "A long project heading" :todo "NEXT"
                            :priority "A" :tags ("plain" "Work")))
           (glasspane-area-icons '(("Work" . "work")))
           (wide (lambda (_axis) "expanded"))
           (header (cl-letf (((symbol-function 'jetpacs-window-class) wide))
                     (glasspane-org-reader--heading-header record '("Work"))))
           (row (aref (plist-get header :children) 0))
           (headline (aref (plist-get row :children) 0))
           (spans (plist-get headline :spans))
           (areas (aref (plist-get row :children) 1))
           (chip (aref (plist-get areas :children) 0))
           (tags (car (last (append (plist-get header :children) nil)))))
      (should (equal (plist-get (aref spans 0) :text) "NEXT "))
      (should (equal (plist-get (aref spans 0) :color) "#123456"))
      (should (equal (plist-get (aref spans 1) :text) "A long project heading"))
      (should (equal (plist-get areas :arrange) "end"))
      (should (= (plist-get areas :weight) 1))
      (should (equal (plist-get chip :variant) "elevated"))
      (should (equal (plist-get chip :icon) "work"))
      (should (equal (plist-get (aref (plist-get tags :children) 0) :label) "plain"))
      (should (= (length (plist-get tags :children)) 1))
      (should (equal (jetpacs-node->canonical-json header)
                     (jetpacs-node->canonical-json
                      (cl-letf (((symbol-function 'jetpacs-window-class) wide))
                        (glasspane-org-reader--heading-header record '("Work"))))))
      ;; A compact window stacks the Area chips beneath the full-width title.
      (let* ((compact (cl-letf (((symbol-function 'jetpacs-window-class)
                                 (lambda (_axis) "compact")))
                        (glasspane-org-reader--heading-header record '("Work"))))
             (children (append (plist-get compact :children) nil)))
        (should (equal (plist-get (car children) :t) "rich_text"))
        (should (equal (plist-get (cadr children) :t) "flow_row"))
        (should (equal (plist-get (cadr children) :arrange) "start"))
        (should-not (plist-get (cadr children) :weight))
        (should (equal (plist-get (aref (plist-get (cadr children) :children) 0)
                                  :variant)
                       "elevated"))))))

(ert-deftest glasspane-reader-layout-native-drawers-hide-without-editing ()
  "Native drawer actions hide both kinds without changing Org source."
  (with-temp-buffer
    (insert "* TODO Parent\n:PROPERTIES:\n:ID: parent\n:END:\n:LOGBOOK:\nA log entry\n:END:\nKeep this prose.\n")
    (org-mode)
    (let* ((original (buffer-string))
           (record (car (ebp-org-outline-collect (point-min) (point-max) t)))
           (tokens (make-hash-table :test #'eql))
           (jetpacs-buffer-exposed (make-hash-table :test #'equal))
           (drawers (jetpacs-org-render-heading-drawers (plist-get record :pos)))
           (controls (jetpacs-org-render-drawer-controls drawers (buffer-name))))
      (should (= (length controls) 2))
      (cl-letf (((symbol-function 'jetpacs-buffer-defer-refresh) #'ignore))
        (dolist (control controls)
          (should (equal (plist-get control :variant) "tonal"))
          (should (eq (jetpacs-org-render--toggle-drawer
                       (plist-get (plist-get control :on_tap) :args) nil)
                      'accepted)))
        (let ((json (jetpacs-node->canonical-json
                     (apply #'jetpacs-column
                            (glasspane-org-reader--content-nodes
                             record "/tmp/drawers.org" tokens)))))
          (should-not (string-search "parent" json))
          (should-not (string-search "A log entry" json))
          (should (string-search "Keep this prose." json)))
        (dolist (control (jetpacs-org-render-drawer-controls
                          (glasspane-org-reader--drawers record) (buffer-name)))
          (should-not (plist-get control :variant))
          (should (eq (jetpacs-org-render--toggle-drawer
                       (plist-get (plist-get control :on_tap) :args) nil)
                      'accepted))))
      (should (equal original (buffer-string))))))

(ert-deftest glasspane-reader-layout-icons-switch-linked-panels ()
  "Only the selected drawer has a panel, with an icon matching its control."
  (with-temp-buffer
    (insert "* Parent\n:PROPERTIES:\n:ID: parent\n:END:\nBefore log.\n:LOGBOOK:\nA log entry\n:END:\nAfter log.\n")
    (org-mode)
    (let* ((original (buffer-string))
           (record (car (ebp-org-outline-collect (point-min) (point-max) t)))
           (tokens (make-hash-table :test #'eql))
           (jetpacs-buffer-exposed (make-hash-table :test #'equal)))
      (cl-labels ((render ()
                    (jetpacs-node->canonical-json
                     (apply #'jetpacs-column
                            (glasspane-org-reader--content-nodes
                             record "/tmp/panels.org" tokens))))
                  (controls ()
                    (jetpacs-org-render-drawer-controls
                     (glasspane-org-reader--drawers record) (buffer-name) t))
                  (tap (control)
                    (should (eq (jetpacs-org-render--toggle-drawer
                                 (plist-get (plist-get control :on_tap) :args) nil)
                                'accepted))))
        (cl-letf (((symbol-function 'jetpacs-buffer-defer-refresh) #'ignore))
          (let ((json (render)))
            (should (string-search "Properties" json))
            (should (string-search "tune" json))
            (should-not (string-search "A log entry" json))
            (should (equal json (render))))
          (tap (cadr (controls)))
          (let ((json (render)) (buttons (controls)))
            (should-not (string-search "parent" json))
            (should (string-search "A log entry" json))
            (should (string-search "history" json))
            (should (string-search "outlined" json))
            (should (string-search "Before log." json))
            (should (string-search "After log." json))
            (should-not (string-search "collapsible" json))
            (should-not (string-search ":END:" json))
            (should-not (plist-get (car buttons) :color))
            (should (equal (plist-get (cadr buttons) :color) "primary"))
            (should (equal json (render))))
          (tap (cadr (controls)))
          (should-not (string-search "outlined" (render)))
          (tap (car (controls)))
          (should (string-search "parent" (render)))
          (should (equal original (buffer-string))))))))

(ert-deftest glasspane-reader-layout-area-memberships-match-projects ()
  "File and inherited Areas appear beside a child's title, like Projects."
  (let* ((vault (make-temp-file "glasspane-reader-area" t))
         (file (expand-file-name "areas.org" vault))
         (org-directory vault)
         (org-agenda-files (list file))
         (ebp-org-roots (list vault)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TAGS: [ Area : Work Digital ]\n#+FILETAGS: :Digital:\n* Parent :Work:\n** TODO Child :plain:\nBody\n"))
          (with-current-buffer (find-file-noselect file)
            (org-mode)
            (goto-char (point-min))
            (search-forward "** TODO Child")
            (beginning-of-line)
            (let* ((pos (point))
                   (node (car (ebp-org-outline-collect pos (point-max) t)))
                   (item `((file . ,file) (pos . ,pos) (tags . ("plain"))))
                   (areas (glasspane-org-item-tag-group-members
                           item glasspane-area-tag-group))
                   (header (cl-letf (((symbol-function 'jetpacs-window-class)
                                      (lambda (_axis) "expanded")))
                             (plist-get (glasspane-org-reader--heading-node
                                         node file (make-hash-table :test #'eql))
                                        :header)))
                   (json (decode-coding-string
                          (jetpacs-node->canonical-json header) 'utf-8)))
              (should (equal areas '("Work" "Digital")))
              (should (string-search "Work" json))
              (should (string-search "Digital" json))
              (should (string-search "plain" json))
              (should (string-search "elevated" json))
              (should (string-search "\"arrange\":\"end\"" json)))))
      (when-let* ((buffer (find-buffer-visiting file))) (kill-buffer buffer))
      (delete-directory vault t))))

(ert-deftest glasspane-reader-layout-open-uses-the-heading-token ()
  "Long press and the menu's Open item share one heading authority.
The header carries no separate open icon, and Archive lives only in the
swipe, not in the overflow menu."
  (let ((tokens (make-hash-table :test #'eql)))
    (puthash 1 '("heading-token" . "archive-token") tokens)
    (cl-letf (((symbol-function 'jetpacs-buffer-expose) #'ignore)
              ((symbol-function 'ebp-org-clocked-in-p) #'ignore))
      (let* ((node (glasspane-org-reader--heading-node
                    '(:pos 1 :title "Heading") "/tmp/reader.org" tokens))
             (header (plist-get node :header))
             (children (append (plist-get header :children) nil))
             (menu (car (last children)))
             (items (append (plist-get menu :items) nil))
             (open (car items)))
        (should (= (length children) 2))
        (should-not (seq-some (lambda (child)
                                (equal (plist-get child :t) "icon_button"))
                              children))
        (should (equal (plist-get menu :t) "menu"))
        (should (equal (plist-get open :label) "Open"))
        (should (equal (plist-get open :on_tap)
                       (plist-get node :on_long_tap)))
        (should (equal (plist-get (plist-get open :on_tap) :args)
                       '(:token "heading-token")))
        (should-not (seq-some (lambda (item)
                                (equal (plist-get item :label) "Archive"))
                              items))
        (should (plist-get node :swipe_end))
        (should (string-search "jetpacs.org.archive"
                               (jetpacs-node->canonical-json node)))))))

(provide 'glasspane-reader-layout-test)
;;; glasspane-reader-layout-test.el ends here
