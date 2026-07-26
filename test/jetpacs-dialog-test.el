;;; jetpacs-dialog-test.el --- JC-4a prompt floor exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JC-4a exit gate (docs/PLAN-jetpacs-consumers.md, JC-4 section).
;; Every test drives the REAL advice through a stubbed
;; `ebp-client-dialog-show', so what is under test is the whole path a
;; prompt takes: gate -> spec build -> SPEC 18.1 advertisement check ->
;; conclusion decoding.  The stub captures the spec, so the assertions
;; are about the actual wire shape, not about a mock's shape.

;;; Code:

(require 'ert)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-dialog)

(defconst jetpacs-dialog-test--dialog-types
  ["text" "row" "column" "box" "spacer" "divider" "button" "text_input"
   "rich_text" "icon" "badge" "section_header" "empty_state" "progress"
   "date_stamp" "checkbox" "switch" "enum_list" "slider"]
  "A dialog profile mirroring the Companion's DIALOG_NODE_TYPES.
Deliberately WITHOUT `card'/`lazy_column'/`editor' — the types the
dialog profile does not advertise, so the gate can be witnessed.")

(defvar jetpacs-dialog-test--specs nil
  "Specs the stub saw, newest first.")

(defvar jetpacs-dialog-test--conclusion nil
  "The (STATUS RESULT ERROR) the stub answers with.")

(defun jetpacs-dialog-test--client ()
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jetpacs-dialog-receipts"))))
    (setf (ebp-client-state client) 'ready
          (ebp-client-granted client) ["surfaces.dialog"]
          (ebp-client-profiles client)
          `(:app (:node_types ,jetpacs-dialog-test--dialog-types
                  :builtins ["view.switch"] :features [])
            :dialog (:node_types ,jetpacs-dialog-test--dialog-types
                     :builtins ["dialog.submit" "dialog.dismiss"]
                     :features []))
          (ebp-client-limits client) '(:max_frame_bytes 4194304))
    client))

(defmacro jetpacs-dialog-test--with-flow (conclusion &rest body)
  "Run BODY inside a device flow with the dialog stub answering CONCLUSION.
CONCLUSION is (STATUS RESULT ERROR) or a function of the spec returning
one, so a test can answer differently per dialog (the confirm loop)."
  (declare (indent 1))
  `(let ((client (jetpacs-dialog-test--client))
         (jetpacs-dialog-test--specs nil)
         (jetpacs-dialog-test--conclusion ,conclusion)
         (jetpacs--device-flow '(:surface "app:demo")))
     (unwind-protect
         (progn
           (jetpacs-attach client)
           (cl-letf (((symbol-function 'ebp-client-dialog-show)
                      (cl-function
                       (lambda (_client _id spec &key callback &allow-other-keys)
                         (push spec jetpacs-dialog-test--specs)
                         (let ((c (if (functionp jetpacs-dialog-test--conclusion)
                                      (funcall jetpacs-dialog-test--conclusion
                                               spec)
                                    jetpacs-dialog-test--conclusion)))
                           (when callback (apply callback c)))
                         42))))
             ,@body))
       (jetpacs-detach)
       (jetpacs-test-reset-state))))

(defmacro jetpacs-dialog-test--quits (&rest body)
  "Non-nil when BODY signals `quit'.
`should-error' cannot express this: `quit' is NOT an `error' subtype,
so its `condition-case' never catches one and the quit escapes the
test.  A dismissed prompt quitting like C-g is a contract this suite
checks repeatedly, so it gets a helper."
  (declare (indent 0) (debug t))
  `(condition-case nil (progn ,@body nil) (quit t)))

(defun jetpacs-dialog-test--walk (node fn)
  (funcall fn node)
  (mapc (lambda (c) (jetpacs-dialog-test--walk c fn))
        (append (plist-get node :children) nil)))

(defun jetpacs-dialog-test--find (spec type)
  "The first node of TYPE in SPEC, or nil."
  (catch 'found
    (jetpacs-dialog-test--walk
     spec (lambda (n) (when (equal (plist-get n :t) type) (throw 'found n))))
    nil))

(defun jetpacs-dialog-test--types (spec)
  (let (types)
    (jetpacs-dialog-test--walk spec (lambda (n) (push (plist-get n :t) types)))
    (nreverse types)))

;;;; The gate

(ert-deftest jetpacs-dialog-gate-only-in-device-flow ()
  "Outside a device flow every advice is a passthrough.
This is what keeps desktop Emacs usable with the module loaded: a
prompt at the keyboard must never be hijacked to a device nobody is
holding."
  (let ((client (jetpacs-dialog-test--client)))
    (unwind-protect
        (progn
          (jetpacs-attach client)
          ;; No flow marker: the bridge declines.
          (should-not (jetpacs-dialog--bridge-p))
          (cl-letf (((symbol-function 'ebp-client-dialog-show)
                     (lambda (&rest _) (error "must not bridge"))))
            (should (equal (cl-letf (((symbol-function 'read-string)
                                      (lambda (&rest _) "typed")))
                             (read-string "Name: "))
                           "typed"))))
      (jetpacs-detach)
      (jetpacs-test-reset-state))))

(ert-deftest jetpacs-dialog-gate-never-inside-dispatch ()
  "A handler that prompts is a D2 violation and MUST fail as one.
The no-prompts regime has to keep winning: if bridging outranked it, a
handler's prompt would silently become a dialog and block the jsonrpc
dispatch extent — the exact hang D2 exists to prevent."
  (let ((client (jetpacs-dialog-test--client)))
    (unwind-protect
        (progn
          (jetpacs-attach client)
          (let ((jetpacs--device-flow '(:surface "app:demo")))
            ;; Inside the dispatch extent: no bridging…
            (let ((jetpacs--in-action-handler t))
              (should-not (jetpacs-dialog--bridge-p)))
            ;; …and `inhibit-interaction' alone also refuses.
            (let ((inhibit-interaction t))
              (should-not (jetpacs-dialog--bridge-p)))
            ;; The real thing: the shim answers `rejected', never hangs.
            (with-jetpacs-owner "demo"
              (jetpacs-defaction "demo.prompts"
                                 (lambda (_a _p) (y-or-n-p "Really? ") 'accepted)))
            (should (equal (ebp-client--handle-event-action
                            client (list :event_id (make-string 32 ?a)
                                         :action "demo.prompts" :args nil
                                         :surface "app:demo" :revision_seen 1
                                         :occurred_at_ms 1785000000000))
                           '(:status "rejected")))
            (jetpacs-undefaction "demo.prompts")))
      (jetpacs-detach)
      (jetpacs-test-reset-state))))

(ert-deftest jetpacs-dialog-flow-continue-carries-the-marker ()
  "`jetpacs-flow-continue' is what makes a prompt reachable at all.
D2 moves interaction into a continuation, where `jetpacs-in-action-p'
is nil — without the carried marker nothing would distinguish
device-originated work from desktop work, and prompts could not bridge."
  (let ((client (jetpacs-dialog-test--client))
        (seen :unset)
        (surface :unset))
    (unwind-protect
        (progn
          (jetpacs-attach client)
          (with-jetpacs-owner "demo"
            (jetpacs-defaction
             "demo.defer"
             (lambda (_a _p)
               ;; Inside the handler: not a prompting context…
               (should-not (jetpacs-dialog--bridge-p))
               (jetpacs-flow-continue
                (lambda ()
                  (setq seen (jetpacs-device-flow-p)
                        surface (jetpacs-flow-surface))))
               'accepted)))
          (should (equal (ebp-client--handle-event-action
                          client (list :event_id (make-string 32 ?b)
                                       :action "demo.defer" :args nil
                                       :surface "app:demo" :revision_seen 1
                                       :occurred_at_ms 1785000000000))
                         '(:status "accepted")))
          ;; The continuation runs from a timer.
          (dotimes (_ 20) (accept-process-output nil 0.01))
          (should (eq seen t))
          (should (equal surface "app:demo"))
          (jetpacs-undefaction "demo.defer"))
      (jetpacs-detach)
      (jetpacs-test-reset-state))))

(ert-deftest jetpacs-dialog-gate-refuses-unadvertised-nodes ()
  "SPEC 18.1: every node in a dialog spec MUST be dialog-advertised.
Loud, like the shell's four gates — a silent strip would ship a spec
the Companion answers 1201 to, with the prompt already waiting."
  (jetpacs-dialog-test--with-flow '("dismissed" nil nil)
    (should-error (jetpacs-dialog--ask
                   (jetpacs-column (jetpacs-text "hi")
                                   (jetpacs-card (list (jetpacs-text "no"))))))))

;;;; y-or-n-p

(ert-deftest jetpacs-dialog-y-or-n-p-round-trip ()
  "Yes and No ride the authored `value' of two dialog.submit builtins."
  (jetpacs-dialog-test--with-flow '("submitted" (:value t) nil)
    (should (eq (y-or-n-p "Delete it? ") t))
    (let ((spec (car jetpacs-dialog-test--specs)))
      ;; The title drops the minibuffer's trailing punctuation.
      (should (equal (plist-get (jetpacs-dialog-test--find spec "text") :text)
                     "Delete it?"))
      ;; Two submit buttons carrying t / :json-false, plus Cancel.
      (let (values)
        (jetpacs-dialog-test--walk
         spec (lambda (n)
                (when-let* ((tap (plist-get n :on_tap)))
                  (push (list (plist-get tap :builtin)
                              (plist-get tap :value))
                        values))))
        (should (equal (nreverse values)
                       '(("dialog.submit" t)
                         ("dialog.submit" :json-false)
                         ("dialog.dismiss" nil)))))))
  ;; A false submission and a dismissal both answer nil / quit.
  (jetpacs-dialog-test--with-flow '("submitted" (:value :json-false) nil)
    (should (eq (y-or-n-p "Delete it? ") nil)))
  ;; A dismissal quits, exactly like C-g at the minibuffer would.
  (jetpacs-dialog-test--with-flow '("dismissed" nil nil)
    (should (jetpacs-dialog-test--quits (y-or-n-p "Delete it? "))))
  ;; So does an error conclusion (1301 after a cancel, transport loss):
  ;; for the prompt's caller every one of them is "no answer".
  (jetpacs-dialog-test--with-flow '(nil nil (:code 1301))
    (should (jetpacs-dialog-test--quits (y-or-n-p "Delete it? ")))))

;;;; read-string / read-from-minibuffer

(ert-deftest jetpacs-dialog-read-string-round-trip ()
  "The typed value arrives in `fields', and the field's Done key
submits — the same on_submit builtin the A8 device smoke verified."
  (jetpacs-dialog-test--with-flow '("submitted" (:fields (:in "hello")) nil)
    (should (equal (read-string "Name: ") "hello"))
    (let* ((spec (car jetpacs-dialog-test--specs))
           (input (jetpacs-dialog-test--find spec "text_input")))
      (should (equal (plist-get input :id) "in"))
      (should (eq (plist-get input :single_line) t))
      (should (equal (plist-get (plist-get input :on_submit) :builtin)
                     "dialog.submit"))
      (should (equal (append (plist-get (plist-get input :on_submit)
                                        :capture_fields) nil)
                     '("in")))))
  ;; An empty submission takes DEFAULT, exactly like RET on empty input.
  (jetpacs-dialog-test--with-flow '("submitted" (:fields (:in "")) nil)
    (should (equal (read-string "Name: " nil nil "fallback") "fallback")))
  ;; INITIAL seeds the field so an immediate submit returns it.
  (jetpacs-dialog-test--with-flow '("submitted" (:fields (:in "seed")) nil)
    (should (equal (read-string "Name: " "seed") "seed"))
    (should (equal (plist-get (jetpacs-dialog-test--find
                               (car jetpacs-dialog-test--specs) "text_input")
                              :value)
                   "seed"))))

(ert-deftest jetpacs-dialog-read-from-minibuffer-read-flag ()
  "READ non-nil reads the answer as a Lisp object, as the minibuffer would."
  (jetpacs-dialog-test--with-flow '("submitted" (:fields (:in "(1 2)")) nil)
    (should (equal (read-from-minibuffer "Expr: " nil nil t) '(1 2)))))

;;;; read-passwd

(ert-deftest jetpacs-dialog-read-passwd-captures-and-clears ()
  "The secret rides `fields' (SPEC 18.1/14.6), the field is a password
field, and the conclusion's copy is cleared — only the returned string
survives."
  (let ((captured nil))
    (jetpacs-dialog-test--with-flow
        (lambda (_spec)
          (setq captured (copy-sequence "s3cret"))
          (list "submitted" (list :fields (list :pw captured)) nil))
      (should (equal (read-passwd "Password: ") "s3cret"))
      (let ((input (jetpacs-dialog-test--find
                    (car jetpacs-dialog-test--specs) "text_input")))
        (should (eq (plist-get input :password) t))
        (should (equal (append (plist-get (plist-get input :on_submit)
                                          :capture_fields) nil)
                       '("pw"))))
      ;; The plist's copy was wiped in place.
      (should (equal captured (make-string 6 0))))))

(ert-deftest jetpacs-dialog-read-passwd-confirm-loop ()
  "CONFIRM re-asks until two entries match, like the minibuffer."
  (let ((answers '("first" "second" "same" "same")))
    (jetpacs-dialog-test--with-flow
        (lambda (_spec)
          (list "submitted" (list :fields (list :pw (copy-sequence
                                                     (pop answers))))
                nil))
      (cl-letf (((symbol-function 'sit-for) (lambda (&rest _) t)))
        (should (equal (read-passwd "New password: " t) "same")))
      ;; Four dialogs: two mismatched, then two matching.
      (should (= (length jetpacs-dialog-test--specs) 4)))))

;;;; read-char family

(ert-deftest jetpacs-dialog-read-char-choice-offers-buttons ()
  "Each legal char is its own submit button; the value returns a char."
  (jetpacs-dialog-test--with-flow '("submitted" (:value "b") nil)
    (should (eq (read-char-choice "Pick: " '(?a ?b ?c)) ?b))
    (let (labels)
      (jetpacs-dialog-test--walk
       (car jetpacs-dialog-test--specs)
       (lambda (n) (when (equal (plist-get n :t) "button")
                     (push (plist-get n :label) labels))))
      (should (equal (nreverse labels) '("a" "b" "c" "Cancel"))))))

;;;; completing-read

(ert-deftest jetpacs-dialog-completing-read-enum-fast-path ()
  "A small closed collection is a native `enum_list' (decision 1)."
  (jetpacs-dialog-test--with-flow '("submitted" (:fields (:pick "beta")) nil)
    (should (equal (completing-read "Pick: " '("alpha" "beta" "gamma") nil t)
                   "beta"))
    (let* ((spec (car jetpacs-dialog-test--specs))
           (enum (jetpacs-dialog-test--find spec "enum_list")))
      (should enum)
      (should (equal (plist-get enum :id) "pick"))
      ;; require-match forbids free-text additions.
      (should (eq (plist-get enum :allow_add) :json-false))
      (should (equal (mapcar (lambda (o) (plist-get o :value))
                             (append (plist-get enum :options) nil))
                     '("alpha" "beta" "gamma")))
      ;; No layout node the dialog profile lacks.
      (should-not (cl-intersection (jetpacs-dialog-test--types spec)
                                   '("card" "lazy_column" "flow_row")
                                   :test #'equal))))
  ;; Without require-match the picker accepts a new value.
  (jetpacs-dialog-test--with-flow '("submitted" (:fields (:pick "delta")) nil)
    (should (equal (completing-read "Pick: " '("alpha" "beta") nil nil)
                   "delta"))
    (should (eq (plist-get (jetpacs-dialog-test--find
                            (car jetpacs-dialog-test--specs) "enum_list")
                           :allow_add)
                t))))

(ert-deftest jetpacs-dialog-completing-read-multiple-enum ()
  "`completing-read-multiple' is the same picker, multi-select."
  (jetpacs-dialog-test--with-flow
      '("submitted" (:fields (:picks ["a" "c"])) nil)
    (should (equal (completing-read-multiple "Pick: " '("a" "b" "c") nil t)
                   '("a" "c")))
    (should (eq (plist-get (jetpacs-dialog-test--find
                            (car jetpacs-dialog-test--specs) "enum_list")
                           :multi_select)
                t))))

;;;; The JC-4b capf picker

(defconst jetpacs-dialog-test--picker-types
  (vconcat jetpacs-dialog-test--dialog-types ["editor"])
  "The dialog profile once JC-4b advertises `editor' for dialogs.")

(defun jetpacs-dialog-test--picker-client ()
  "A client whose dialog profile hosts editors and grants editor.sync."
  (let ((client (jetpacs-dialog-test--client)))
    (setf (ebp-client-granted client) ["surfaces.dialog" "editor.sync"]
          (ebp-client-profiles client)
          `(:app (:node_types ,jetpacs-dialog-test--picker-types
                  :builtins ["view.switch"] :features [])
            :dialog (:node_types ,jetpacs-dialog-test--picker-types
                     :builtins ["dialog.submit" "dialog.dismiss"]
                     :features [])))
    client))

(ert-deftest jetpacs-dialog-picker-availability-gate ()
  "The picker needs BOTH editor.sync granted and `editor' advertised for
dialogs; otherwise the JC-4a text stopgap runs, never a spec violation."
  (let ((client (jetpacs-dialog-test--client)))   ; no editor.sync, no editor
    (unwind-protect
        (progn (jetpacs-attach client)
               (should-not (jetpacs-dialog--picker-available-p)))
      (jetpacs-detach) (jetpacs-test-reset-state)))
  (let ((client (jetpacs-dialog-test--picker-client)))
    (unwind-protect
        (progn (jetpacs-attach client)
               (should (jetpacs-dialog--picker-available-p))
               ;; Capability without advertisement is still a no.
               (setf (ebp-client-profiles client)
                     `(:dialog (:node_types ,jetpacs-dialog-test--dialog-types
                                :builtins [] :features [])))
               (should-not (jetpacs-dialog--picker-available-p)))
      (jetpacs-detach) (jetpacs-test-reset-state))))

(ert-deftest jetpacs-dialog-picker-completes-from-the-collection ()
  "`edit.complete' is answered from the COLLECTION being completed.
Driven through ebp's real `ebp-client--handle-edit-complete', so the
session/seq gate and the result shape are the live ones, not a mock's."
  (let ((client (jetpacs-dialog-test--picker-client)))
    (unwind-protect
        (progn
          (jetpacs-attach client)
          ;; Stand in for the dialog's live editor session.
          (puthash (cons "doc:p" "pick")
                   (list :session "S1" :seq 3 :text "ca" :cursor 2)
                   (ebp-client-editors client))
          (setf (ebp-client-config client)
                (plist-put (ebp-client-config client)
                           :edit-complete-function
                           #'jetpacs-dialog--complete))
          (let ((jetpacs-dialog--picker
                 '(:document "doc:p" :editor-id "pick"
                   :collection ("cabbage" "cactus" "cat" "dog")
                   :predicate nil)))
            (let ((result (ebp-client--handle-edit-complete
                           client '(:document "doc:p" :editor_id "pick"
                                    :session "S1" :seq 3 :cursor 2))))
              (should (equal (plist-get result :prefix) "ca"))
              (should (equal (mapcar (lambda (c) (plist-get c :label))
                                     (append (plist-get result :candidates) nil))
                             '("cabbage" "cactus" "cat")))))
          ;; A request for a DIFFERENT editor than the live picker's gets
          ;; nothing — the hook is client-wide, the picker is not.
          (let ((jetpacs-dialog--picker
                 '(:document "doc:other" :editor-id "pick"
                   :collection ("cat") :predicate nil)))
            (should (equal (plist-get (ebp-client--handle-edit-complete
                                       client '(:document "doc:p"
                                                :editor_id "pick"
                                                :session "S1" :seq 3 :cursor 2))
                                      :candidates)
                           [])))
          ;; A stale seq is refused by ebp before the hook is consulted.
          (should-error (ebp-client--handle-edit-complete
                         client '(:document "doc:p" :editor_id "pick"
                                  :session "S1" :seq 99 :cursor 2))))
      (jetpacs-detach) (jetpacs-test-reset-state))))

(ert-deftest jetpacs-dialog-picker-candidate-count-is-bounded ()
  "A huge collection answers at most `jetpacs-dialog-picker-candidates'."
  (let ((jetpacs-dialog--picker
         (list :document "d" :editor-id "e"
               :collection (cl-loop for i from 0 below 500
                                    collect (format "cand-%03d" i))
               :predicate nil))
        (jetpacs-dialog-picker-candidates 12))
    (let ((r (jetpacs-dialog--complete "d" "e" "cand-" 5)))
      (should (equal (car r) "cand-"))
      (should (= (length (cdr r)) 12)))))

(ert-deftest jetpacs-dialog-picker-uses-completion-boundaries ()
  "The replaced prefix is the completion FIELD, not the whole input.
A file-name table completes one path component, so tapping a candidate
must replace only that component — the boundary decides where the
prefix starts, and getting it wrong rewrites the whole path."
  (let* ((table (lambda (str pred action)
                  (if (eq (car-safe action) 'boundaries)
                      (let ((slash (1+ (or (cl-position ?/ str :from-end t) -1))))
                        `(boundaries ,slash . ,(length (cdr action))))
                    (complete-with-action
                     action '("src/alpha.el" "src/beta.el") str pred))))
         (jetpacs-dialog--picker (list :document "d" :editor-id "e"
                                       :collection table :predicate nil)))
    (let ((r (jetpacs-dialog--complete "d" "e" "src/al" 6)))
      ;; The prefix is "al", not "src/al".
      (should (equal (car r) "al")))))

(ert-deftest jetpacs-dialog-picker-round-trip-and-restore ()
  "The picker reads the MIRROR, not `capture_fields' — a synchronized
editor is never a stateful node — and restores the client-wide
completion hook it borrowed."
  (let ((client (jetpacs-dialog-test--picker-client))
        (jetpacs-dialog-test--specs nil))
    (unwind-protect
        (progn
          (jetpacs-attach client)
          (setf (ebp-client-config client)
                (plist-put (ebp-client-config client)
                           :edit-complete-function 'app-hook))
          (cl-letf (((symbol-function 'ebp-client-dialog-show)
                     (cl-function
                      (lambda (c _id spec &key callback &allow-other-keys)
                        (push spec jetpacs-dialog-test--specs)
                        ;; The device types "cact": edit.delta reaches the
                        ;; mirror hooks, which is how the picker shadows it.
                        (let ((doc (plist-get
                                    (jetpacs-dialog-test--find spec "editor")
                                    :document)))
                          (dolist (fn (ebp-client-edit-change-functions c))
                            (funcall fn c doc "pick" "cact")))
                        (funcall callback "submitted" '(:value nil) nil)
                        7))))
            (let ((jetpacs--device-flow '(:surface "app:demo")))
              (should (equal (completing-read
                              "Pick: "
                              (cl-loop for i from 0 below 80
                                       collect (format "cand-%02d" i))
                              nil nil)
                             "cact"))))
          ;; The spec hosted a synchronized editor asking for completion.
          (let ((ed (jetpacs-dialog-test--find
                     (car jetpacs-dialog-test--specs) "editor")))
            (should ed)
            (should (string-prefix-p "doc:jpick-" (plist-get ed :document)))
            (should (eq (plist-get ed :complete) t)))
          ;; Borrowed state is given back.
          (should (eq (plist-get (ebp-client-config client)
                                 :edit-complete-function)
                      'app-hook))
          (should-not jetpacs-dialog--picker))
      (jetpacs-detach) (jetpacs-test-reset-state))))

(ert-deftest jetpacs-dialog-picker-survives-the-closing-edit-close ()
  "SPEC 18.1 closes a dialog's editor sessions BEFORE the submit
response, and ebp fires `edit-change-functions' on that close with the
session already removed — so the hook arrives with text nil.  The
shadow must keep the last real text: without the guard the close wiped
it at exactly the moment the picker read it and the prompt died on
`stringp nil' with the user's answer already typed.

Device-caught.  No stub had ever fired a close, which is precisely why
five green unit tests missed it — this one drives ebp's REAL
`ebp-client--handle-edit-close'."
  (let ((client (jetpacs-dialog-test--picker-client))
        (jetpacs-dialog-test--specs nil))
    (unwind-protect
        (progn
          (jetpacs-attach client)
          (cl-letf (((symbol-function 'ebp-client-dialog-show)
                     (cl-function
                      (lambda (c _id spec &key callback &allow-other-keys)
                        (push spec jetpacs-dialog-test--specs)
                        (let ((doc (plist-get
                                    (jetpacs-dialog-test--find spec "editor")
                                    :document)))
                          ;; The user types...
                          (puthash (cons doc "pick")
                                   (list :session "S" :seq 1 :text "cand-4"
                                         :cursor 6)
                                   (ebp-client-editors c))
                          (dolist (fn (ebp-client-edit-change-functions c))
                            (funcall fn c doc "pick" "cand-4"))
                          ;; ...then SPEC 18.1 closes the session before the
                          ;; response, through ebp's real close handler.
                          (ebp-client--handle-edit-close
                           c (list :document doc :editor_id "pick"
                                   :session "S")))
                        (funcall callback "submitted" '(:value nil) nil)
                        7))))
            (let ((jetpacs--device-flow '(:surface "app:demo")))
              ;; The answer survives the close and resolves top-match.
              (should (equal (completing-read
                              "Pick: "
                              (cl-loop for i from 0 below 80
                                       collect (format "cand-%02d" i))
                              nil t)
                             "cand-40")))))
      (jetpacs-detach) (jetpacs-test-reset-state))))

(ert-deftest jetpacs-dialog-picker-resolves-top-match ()
  "A typed prefix resolves RET-picks-top against the collection."
  (let ((client (jetpacs-dialog-test--picker-client))
        (jetpacs-dialog-test--specs nil))
    (unwind-protect
        (progn
          (jetpacs-attach client)
          (cl-letf (((symbol-function 'ebp-client-dialog-show)
                     (cl-function
                      (lambda (c _id spec &key callback &allow-other-keys)
                        (push spec jetpacs-dialog-test--specs)
                        (let ((doc (plist-get
                                    (jetpacs-dialog-test--find spec "editor")
                                    :document)))
                          (dolist (fn (ebp-client-edit-change-functions c))
                            (funcall fn c doc "pick" "cand-1")))
                        (funcall callback "submitted" '(:value nil) nil)
                        7))))
            (let ((jetpacs--device-flow '(:surface "app:demo")))
              ;; "cand-1" is not an exact completion; the top match wins.
              (should (equal (completing-read
                              "Pick: "
                              (cl-loop for i from 0 below 80
                                       collect (format "cand-%02d" i))
                              nil t)
                             "cand-10")))))
      (jetpacs-detach) (jetpacs-test-reset-state))))

(ert-deftest jetpacs-dialog-completing-read-large-uses-stopgap ()
  "Over the threshold the 4a stopgap runs: a text dialog resolved
RET-picks-top.  JC-4b replaces this with the live capf picker."
  (let* ((big (cl-loop for i from 0 below 60 collect (format "cand-%02d" i)))
         (jetpacs-dialog-enum-threshold 50))
    (jetpacs-dialog-test--with-flow '("submitted" (:fields (:in "cand-1")) nil)
      ;; "cand-1" is not an exact completion; the top match wins.
      (should (equal (completing-read "Pick: " big nil t) "cand-10"))
      (let ((spec (car jetpacs-dialog-test--specs)))
        (should (jetpacs-dialog-test--find spec "text_input"))
        (should-not (jetpacs-dialog-test--find spec "enum_list"))))))

(ert-deftest jetpacs-dialog-completing-read-dynamic-uses-stopgap ()
  "A function collection cannot be enumerated, so it takes the stopgap
even when it would answer few candidates."
  (let ((table (lambda (str pred action)
                 (complete-with-action action '("dyn-one" "dyn-two")
                                       str pred))))
    (jetpacs-dialog-test--with-flow '("submitted" (:fields (:in "dyn-o")) nil)
      (should (equal (completing-read "Pick: " table nil t) "dyn-one"))
      (should-not (jetpacs-dialog-test--find (car jetpacs-dialog-test--specs)
                                             "enum_list")))))

;;;; Context cards

(ert-deftest jetpacs-dialog-context-cards-are-budgeted-and-inert ()
  "Decision 2: context renders INSIDE the dialog as section_header plus
Tier-0 spans, with every interactive attribute stripped and only
dialog-advertised types used."
  (let ((buf (get-buffer-create "*jetpacs-dialog-context*")))
    (unwind-protect
        (progn
          (with-current-buffer buf
            (erase-buffer)
            (insert "context line one\ncontext line two\n"))
          (jetpacs-dialog-test--with-flow '("submitted" (:value t) nil)
            (jetpacs-dialog--record-context buf)
            (should (member "*jetpacs-dialog-context*"
                            jetpacs-dialog--context-buffers))
            (y-or-n-p "Proceed? ")
            (let ((spec (car jetpacs-dialog-test--specs)))
              ;; The header names the buffer…
              (should (equal (plist-get (jetpacs-dialog-test--find
                                         spec "section_header")
                                        :title)
                             "*jetpacs-dialog-context*"))
              ;; …every type is dialog-advertised…
              (dolist (type (jetpacs-dialog-test--types spec))
                (should (jetpacs-node-advertised-p type :dialog)))
              ;; …and nothing in the context subtree is interactive
              ;; except the prompt's own buttons.
              (let ((taps 0))
                (jetpacs-dialog-test--walk
                 spec (lambda (n) (when (plist-get n :on_tap) (cl-incf taps))))
                (should (= taps 3))))
            ;; The record is consumed: the next prompt is clean.
            (should-not jetpacs-dialog--context-buffers)))
      (kill-buffer buf))))

;;;; Boundary

(ert-deftest jetpacs-dialog-registers-no-actions ()
  "The rebuild owns no action names: `prompt.reply'/`.dismiss'/`.toggle'
ceased to exist when dialogs became requests (SPEC 18.1).  A leftover
registration would be a silent contract regression."
  (let ((client (jetpacs-dialog-test--client)))
    (unwind-protect
        (progn
          (jetpacs-attach client)
          (dolist (name '("prompt.reply" "prompt.dismiss" "prompt.toggle"))
            (should-not (gethash name (ebp-client-actions client)))
            (should-not (gethash name jetpacs-action-handlers))))
      (jetpacs-detach)
      (jetpacs-test-reset-state))))

(ert-deftest jetpacs-dialog-single-flight ()
  "A second bridged prompt inside an outstanding one must not nest
waits; it declines and falls through to the original function."
  (jetpacs-dialog-test--with-flow '("submitted" (:value t) nil)
    (let ((jetpacs-dialog--pending "jprompt-1"))
      (should-not (jetpacs-dialog--bridge-p)))))

;;;; Flow entry (JA-2/B3): establishing a device flow

(ert-deftest jetpacs-flow-with-jetpacs-flow-binds-and-restores ()
  (should-not (jetpacs-device-flow-p))
  (should (= 42 (with-jetpacs-flow "app:demo"
                  (should (jetpacs-device-flow-p))
                  (should (equal (jetpacs-flow-surface) "app:demo"))
                  42)))
  (should-not (jetpacs-device-flow-p)))

(ert-deftest jetpacs-flow-owner-and-default-resolution ()
  (with-jetpacs-flow "demo"
    (should (equal (jetpacs-flow-surface) "app:demo")))
  (with-jetpacs-owner "demo"
    (with-jetpacs-flow nil
      (should (equal (jetpacs-flow-surface) "app:demo"))))
  ;; Ownerless nil: the shell default (shell is loaded by this suite).
  (with-jetpacs-flow nil
    (should (equal (jetpacs-flow-surface) "app:main"))))

(ert-deftest jetpacs-flow-rejects-invalid-surfaces ()
  (should-error (with-jetpacs-flow "no spaces" (ignore)))
  (should-error (with-jetpacs-flow "bogus:x" (ignore)))
  (should-error (with-jetpacs-flow "app:" (ignore)))
  (should-error (with-jetpacs-flow 42 (ignore)))
  ;; flow-begin validates EAGERLY on the caller's stack — no pumping.
  (should-error (jetpacs-flow-begin "app:" #'ignore))
  (should-error (jetpacs-flow-begin "app:demo" "not-a-fn"))
  (should-not (jetpacs-device-flow-p)))

(ert-deftest jetpacs-flow-marker-cleared-on-error-and-quit ()
  (should-error (with-jetpacs-flow "app:demo" (error "boom")))
  (should-not (jetpacs-device-flow-p))
  (should (jetpacs-dialog-test--quits
            (with-jetpacs-flow "app:demo" (keyboard-quit))))
  (should-not (jetpacs-device-flow-p)))

(ert-deftest jetpacs-flow-nested-same-ok-different-refused ()
  (with-jetpacs-flow "app:demo"
    ;; Same surface (either spelling): idempotent.
    (with-jetpacs-flow "app:demo"
      (should (equal (jetpacs-flow-surface) "app:demo")))
    (with-jetpacs-flow "demo"
      (should (equal (jetpacs-flow-surface) "app:demo")))
    ;; A different surface refuses; the outer flow survives.
    (should-error (with-jetpacs-flow "app:other" (ignore)))
    (should (equal (jetpacs-flow-surface) "app:demo"))))

(ert-deftest jetpacs-flow-begin-marks-from-a-bare-timer ()
  (let ((seen :unset) (surface :unset))
    (jetpacs-flow-begin "app:demo"
                        (lambda ()
                          (setq seen (jetpacs-device-flow-p)
                                surface (jetpacs-flow-surface))))
    ;; The caller stays unmarked — the flow is deferred.
    (should-not (jetpacs-device-flow-p))
    (dotimes (_ 20) (accept-process-output nil 0.01))
    (should (eq seen t))
    (should (equal surface "app:demo"))
    (should-not (jetpacs-device-flow-p))))

(ert-deftest jetpacs-flow-begin-chains-through-flow-continue ()
  (let ((chained :unset))
    (jetpacs-flow-begin "app:demo"
                        (lambda ()
                          (jetpacs-flow-continue
                           (lambda ()
                             (setq chained (jetpacs-flow-surface))))))
    (dotimes (_ 30) (accept-process-output nil 0.01))
    (should (equal chained "app:demo"))))

(ert-deftest jetpacs-flow-does-not-unlock-dispatch-extent ()
  "A flow begun INSIDE a handler cannot unlock prompts there: the
no-prompts regime and the in-action test still win (D2)."
  (let ((client (jetpacs-dialog-test--client))
        (bridged :unset))
    (unwind-protect
        (progn
          (jetpacs-attach client)
          (with-jetpacs-owner "demo"
            (jetpacs-defaction "demo.flowbegun"
              (lambda (_a _p)
                (with-jetpacs-flow "app:demo"
                  (setq bridged (jetpacs-dialog--bridge-p))
                  (y-or-n-p "Really? "))
                'accepted)))
          (let ((reply (ebp-client--handle-event-action
                        client
                        (list :event_id (make-string 32 ?c)
                              :action "demo.flowbegun" :args nil
                              :surface "app:demo" :revision_seen 1
                              :occurred_at_ms 1785000000000))))
            (should (equal (plist-get reply :status) "rejected")))
          (should-not bridged))
      (jetpacs-detach)
      (jetpacs-test-reset-state))))

(ert-deftest jetpacs-flow-bridges-prompt-to-dialog ()
  "Both entry points reach the JC-4a bridge: a prompt raised inside an
ESTABLISHED flow lands on the dialog seam with the flow's surface."
  (let ((client (jetpacs-dialog-test--client))
        (jetpacs-dialog-test--specs nil)
        (jetpacs-dialog-test--conclusion '("submitted" (:value t) nil))
        (answer :unset) (fsurf :unset))
    (unwind-protect
        (cl-letf (((symbol-function 'ebp-client-dialog-show)
                   (cl-function
                    (lambda (_client _id spec &key callback
                             &allow-other-keys)
                      (push spec jetpacs-dialog-test--specs)
                      (when callback
                        (apply callback jetpacs-dialog-test--conclusion))
                      42))))
          (jetpacs-attach client)
          ;; with-jetpacs-flow from a bare timer.
          (run-at-time 0 nil
                       (lambda ()
                         (with-jetpacs-flow "app:demo"
                           (setq answer (y-or-n-p "Push? ")
                                 fsurf (jetpacs-flow-surface)))))
          (let ((deadline (+ (float-time) 3)))
            (while (and (eq answer :unset) (< (float-time) deadline))
              (accept-process-output nil 0.05)))
          (should (eq answer t))
          (should (equal fsurf "app:demo"))
          (should (= 1 (length jetpacs-dialog-test--specs)))
          ;; jetpacs-flow-begin reaches the same bridge.
          (setq answer :unset)
          (jetpacs-flow-begin "app:demo"
                              (lambda ()
                                (setq answer (y-or-n-p "Push? "))))
          (let ((deadline (+ (float-time) 3)))
            (while (and (eq answer :unset) (< (float-time) deadline))
              (accept-process-output nil 0.05)))
          (should (eq answer t))
          (should (= 2 (length jetpacs-dialog-test--specs))))
      (jetpacs-detach)
      (jetpacs-test-reset-state))))


(ert-deftest jetpacs-dialog-bridge-requires-the-dialog-grant ()
  "P1-5: dialog.show is capability-gated (SPEC 10.2 / method registry).
Without surfaces.dialog the bridge must decline so the prompt falls
through to a usable minibuffer, instead of sending, earning -32601, and
aborting the caller's command."
  (let ((client (jetpacs-dialog-test--client)))
    (unwind-protect
        (progn
          (jetpacs-attach client)
          (let ((jetpacs--device-flow '(:surface "app:demo")))
            (should (jetpacs-dialog--bridge-p))
            (setf (ebp-client-granted client) ["theme"])
            (should-not (jetpacs-dialog--bridge-p))))
      (jetpacs-detach)
      (jetpacs-test-reset-state))))

(ert-deftest jetpacs-dialog-gate-spec-refuses-an-ungranted-wake ()
  "P1-4: a dialog button's descriptor reaches the wire by the dialog
path, so the 14.1 policy gate runs there too."
  (let ((client (jetpacs-dialog-test--client)))
    (unwind-protect
        (progn
          (jetpacs-attach client)
          (let ((spec (jetpacs-column
                       (jetpacs-button "Go" (jetpacs-action
                                             "a.b" :when-offline 'wake
                                             :ttl-s 60)))))
            (should-error (jetpacs-dialog--gate-spec spec)))
          (setf (ebp-client-granted client) ["surfaces.dialog" "offline.wake"])
          (should (jetpacs-dialog--gate-spec
                   (jetpacs-column
                    (jetpacs-button "Go" (jetpacs-action
                                          "a.b" :when-offline 'wake
                                          :ttl-s 60))))))
      (jetpacs-detach)
      (jetpacs-test-reset-state))))

(provide 'jetpacs-dialog-test)
;;; jetpacs-dialog-test.el ends here
