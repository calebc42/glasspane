;;; glasspane-vulpea-test.el --- Tests for the mobile-context vulpea extractor
;;; Code:

(require 'glasspane-test-helpers)
(require 'cl-lib)
(require 'glasspane-vulpea)

(defmacro glasspane-vulpea-tests--with-db-capture (captured &rest body)
  "Run BODY with `emacsql'/`vulpea-db' stubbed; calls land in CAPTURED.
Each capture is (SQL . ARGS), newest first."
  (declare (indent 1))
  `(let ((,captured nil))
     (cl-letf (((symbol-function 'vulpea-db) (lambda () 'fake-db))
               ((symbol-function 'emacsql)
                (lambda (_db sql &rest args)
                  (push (cons sql args) ,captured)
                  nil)))
       ,@body)))

(ert-deftest glasspane-vulpea-extract-inserts-mobile-row ()
  "A note with mobile properties inserts one row keyed to the note id.
Column order matches the schema; BATTERY_LEVEL becomes a number,
absent properties become nil (SQL NULL)."
  (glasspane-vulpea-tests--with-db-capture calls
    (let* ((note-data (list :id "n-1"
                            :properties '(("LOCATION" . "home")
                                          ("BATTERY_LEVEL" . "80")
                                          ("ID" . "n-1"))))
           (result (glasspane-vulpea--extract-mobile nil note-data)))
      (should (eq result note-data))
      (should (= (length calls) 1))
      (should (equal (caar calls)
                     [:insert :into glasspane-mobile :values $v1]))
      (should (equal (cdar calls)
                     (list (vector "n-1" "home" nil 80 nil nil)))))))

(ert-deftest glasspane-vulpea-extract-skips-plain-notes ()
  "A note without mobile properties writes nothing."
  (glasspane-vulpea-tests--with-db-capture calls
    (let ((note-data (list :id "n-2" :properties '(("ID" . "n-2")))))
      (should (eq (glasspane-vulpea--extract-mobile nil note-data) note-data))
      (should-not calls))))

(ert-deftest glasspane-vulpea-extract-skips-without-note-id ()
  "Mobile properties on a node vulpea gave no id are not indexed."
  (glasspane-vulpea-tests--with-db-capture calls
    (let ((note-data (list :properties '(("LOCATION" . "gym")))))
      (should (eq (glasspane-vulpea--extract-mobile nil note-data) note-data))
      (should-not calls))))

(cl-defun glasspane-vulpea-tests--register-slots (&key v26)
  "Drive `glasspane-vulpea-register' twice against mocked vulpea.
V26 non-nil fakes `vulpea-extractor-requires-ast-p' defined (the 2.6
probe); nil forces it undefined.  Asserts once-only registration and
returns the slot plist handed to `make-vulpea-extractor'."
  (let ((glasspane-vulpea--registered nil)
        made registered)
    (cl-letf (((symbol-function 'vulpea-db-register-extractor)
               (lambda (ext) (push ext registered) ext))
              ((symbol-function 'make-vulpea-extractor)
               (lambda (&rest slots) (setq made slots) 'fake-extractor))
              ((symbol-function 'vulpea-extractor-requires-ast-p)
               (and v26 #'ignore)))     ; nil function cell = not fboundp
      (glasspane-vulpea-register)
      (glasspane-vulpea-register))
    ;; Registered exactly once (idempotent flag), with the built struct.
    (should (equal registered '(fake-extractor)))
    made))

(ert-deftest glasspane-vulpea-register-uses-only-v26-slots ()
  "Registration passes only vulpea 2.6 extractor slots, once.
The pre-rewrite file passed `:batch-insert-fn'/`:delete-fn' — slots
2.6's cl-defstruct constructor rejects, so glasspane crashed at load
whenever vulpea was installed.  Pins the 2.6 contract: cascade FK
schema instead of a delete hook, props-only worker eligibility, and
a symbol extract-fn the worker can resolve via `:worker-lib'.
The 2.6 slot trio is gated on `vulpea-extractor-requires-ast-p'
(fake it defined here); its absence is the older-vulpea test below."
  (let ((made (glasspane-vulpea-tests--register-slots :v26 t)))
    (let ((keys (cl-loop for (k _v) on made by #'cddr collect k)))
      (should-not (memq :batch-insert-fn keys))
      (should-not (memq :delete-fn keys))
      (dolist (k keys)
        (should (memq k '(:name :version :schema :priority :extract-fn
                          :requires-ast :worker-safe :worker-lib))))
      ;; Explicit :requires-ast nil (not merely absent — the default is
      ;; the `unset' sentinel) keeps extraction off the full object parse.
      (should (memq :requires-ast keys)))
    (should-not (plist-get made :requires-ast))
    (should (eq (plist-get made :worker-safe) t))
    (should (eq (plist-get made :worker-lib) 'glasspane-vulpea))
    (should (eq (plist-get made :extract-fn) 'glasspane-vulpea--extract-mobile))
    ;; Cascade FK on the plugin table replaces the dead delete-fn.
    (let* ((table (assq 'glasspane-mobile (plist-get made :schema)))
           (fk (cl-find-if (lambda (c) (and (consp c) (eq (car c) :foreign-key)))
                           (cdr table))))
      (should table)
      (should (equal fk '(:foreign-key [note-id] :references notes [id]
                          :on-delete :cascade))))))

(ert-deftest glasspane-vulpea-register-omits-v26-slots-on-older-vulpea ()
  "Pre-2.6 vulpea gets no `:requires-ast'/`:worker-safe'/`:worker-lib'.
Those slots don't exist there and a cl-defstruct constructor signals
on unknown keywords — the same mechanism as the crash this file's
rewrite fixed, just aimed the other way.  Omission is correct, not
degraded: pre-2.6 always populates the AST and has no worker."
  (let ((made (glasspane-vulpea-tests--register-slots :v26 nil)))
    (should made)                       ; still registers
    (let ((keys (cl-loop for (k _v) on made by #'cddr collect k)))
      (dolist (k keys)
        (should (memq k '(:name :version :schema :priority :extract-fn)))))))

(ert-deftest glasspane-vulpea-register-noop-without-vulpea ()
  "Without vulpea's registry loaded, registration quietly does nothing."
  (skip-unless (not (fboundp 'vulpea-db-register-extractor)))
  (let ((glasspane-vulpea--registered nil))
    (glasspane-vulpea-register)
    (should-not glasspane-vulpea--registered)))

(provide 'glasspane-vulpea-test)
;;; glasspane-vulpea-test.el ends here
