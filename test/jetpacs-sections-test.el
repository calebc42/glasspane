;;; jetpacs-sections-test.el --- JC-3a/3c exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; JC-3a (`jetpacs-sections') and JC-3c (`jetpacs-comint') exit gate.
;; magit-section is third-party and absent, so the section tree is a
;; SYNTHETIC eieio class with the slots the substrate reads — which is
;; exactly what the plan's exit gate asks for.

;;; Code:

(require 'ert)
(require 'eieio)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-results)
(require 'jetpacs-sections)
(require 'jetpacs-comint)

;; A stand-in for magit-section carrying only the slots read by the
;; substrate.  `magit-section-ident' is absent, so `--id' takes its
;; documented position fallback.
(defclass jetpacs-test-section ()
  ((start :initarg :start :initform nil)
   (content :initarg :content :initform nil)
   (end :initarg :end :initform nil)
   (children :initarg :children :initform nil)
   (hidden :initarg :hidden :initform nil)
   (washer :initarg :washer :initform nil)))

(defconst jetpacs-sections-test--source
  ;; Captured at LOAD time: `load-file-name' is nil by the time ERT runs a
  ;; test body.
  (expand-file-name "../emacs/jetpacs-sections.el"
                    (file-name-directory
                     (or load-file-name buffer-file-name default-directory)))
  "Path to the module under test, for the source-level D2 assertion.")

(defconst jetpacs-sections-test--full
  '(:app (:node_types ["text" "row" "column" "box" "spacer" "divider"
                       "button" "text_input" "collapsible" "rich_text"
                       "icon" "icon_button"]
          :builtins [] :features []))
  "A profile advertising what these skins want.")

(defconst jetpacs-sections-test--core
  '(:app (:node_types ["text" "row" "column" "box" "spacer" "divider"
                       "button" "text_input"]
          :builtins [] :features []))
  "Core Node Set only — the degrade fixture.")

(cl-defun jetpacs-sections-test--client (&key profiles granted)
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jc3-receipts"))))
    (setf (ebp-client-state client) 'ready
          (ebp-client-limits client) '(:max_frame_bytes 4194304)
          (ebp-client-granted client) (or granted ["theme"])
          (ebp-client-profiles client)
          (or profiles jetpacs-sections-test--full))
    client))

(defmacro jetpacs-sections-test--with-client (spec &rest body)
  (declare (indent 1))
  `(let ((client (jetpacs-sections-test--client ,@spec)))
     (unwind-protect (progn (jetpacs-attach client) ,@body)
       (jetpacs-detach)
       (jetpacs-buffer-forget-exposed))))

(defun jetpacs-sections-test--buffer ()
  "A buffer with a tappable body line, plus a synthetic section tree."
  (with-current-buffer (get-buffer-create "*jc3-sections*")
    (erase-buffer)
    (insert "Section header\n")
    (let ((start (point)))
      (insert "body line with a tap\n")
      ;; A keymap over the body line makes the Tier-0 builder wire a tap.
      (let ((km (make-sparse-keymap)))
        (define-key km (kbd "RET") #'ignore)
        (put-text-property start (1- (point)) 'keymap km)))
    (insert "tail line\n")
    (current-buffer)))

;;;; Span surgery (format 6: spans are PLISTS)

(ert-deftest jetpacs-sections-strip-taps ()
  "Header taps are removed without disturbing the other members."
  (let* ((spans (list (jetpacs-span "a" :mono t
                                    :on-tap (jetpacs-action "x.y"))
                      (jetpacs-span "b" :font-weight "bold")))
         (out (jetpacs-sections--strip-taps spans)))
    (should (= (length out) 2))
    (should-not (plist-get (car out) :on_tap))
    ;; The surviving members are intact — this is the alist->plist rewrite
    ;; the plan flagged, and dropping the wrong key silently mangles nodes.
    (should (equal (plist-get (car out) :text) "a"))
    (should (eq (plist-get (car out) :mono) t))
    (should (equal (plist-get (nth 1 out) :font_weight) "bold"))
    ;; The input is not mutated.
    (should (plist-get (car spans) :on_tap))))

(ert-deftest jetpacs-sections-retarget-taps ()
  "A generic buffer tap becomes `sections.visit' AND is re-exposed under
that verb — SPEC 23.1 records are per-action, so retargeting without
re-exposing would make every tap refused."
  (jetpacs-sections-test--with-client ()
    (jetpacs-buffer-forget-exposed)
    (let* ((args '(:buffer "*jc3-sections*" :pos 17))
           (spans (list (jetpacs-span "hit" :on-tap
                                      (jetpacs-action "emacs.buffer.act"
                                                      :args args))
                        (jetpacs-span "plain")
                        (jetpacs-span "fold" :on-tap
                                      (jetpacs-action "jetpacs.buffer.fold"
                                                      :args args))))
           (out (jetpacs-sections--retarget-taps spans "*jc3-sections*")))
      (should (equal (plist-get (plist-get (nth 0 out) :on_tap) :action)
                     "sections.visit"))
      ;; args survive verbatim
      (should (equal (plist-get (plist-get (nth 0 out) :on_tap) :args) args))
      ;; untapped and fold spans pass through untouched
      (should-not (plist-get (nth 1 out) :on_tap))
      (should (equal (plist-get (plist-get (nth 2 out) :on_tap) :action)
                     "jetpacs.buffer.fold"))
      ;; the position is now exposed for the NEW verb
      (should (jetpacs-buffer-exposed-p "*jc3-sections*" 17 "sections.visit")))))

;;;; Render

(defun jetpacs-sections-test--tree (buf)
  "A synthetic root+child tree over BUF."
  (with-current-buffer buf
    (let* ((child (jetpacs-test-section
                   :start (copy-marker 1)
                   :content (copy-marker 16)
                   :end (copy-marker (point-max))))
           (root (jetpacs-test-section
                  :start (copy-marker 1)
                  :content nil
                  :end (copy-marker (point-max))
                  :children (list child))))
      root)))

(ert-deftest jetpacs-sections-render-tree ()
  "A heading+content section becomes a collapsible whose long-press is
exposed for `sections.menu'."
  (jetpacs-sections-test--with-client ()
    (let* ((buf (jetpacs-sections-test--buffer))
           (root (jetpacs-sections-test--tree buf)))
      (cl-letf (((symbol-function 'jetpacs-sections--root)
                 (lambda () root)))
        (with-current-buffer buf
          (let* ((nodes (let ((budget (cons 500 nil)))
                          (jetpacs-buffer-forget-exposed (buffer-name buf))
                          (jetpacs-sections--emit root (buffer-name buf)
                                                  budget)))
                 (card (car nodes)))
            (should (equal (plist-get card :t) "collapsible"))
            (should (plist-get card :id))
            (should (equal (plist-get (plist-get card :on_long_tap) :action)
                           "sections.menu"))
            ;; The long-press position is exposed for ITS verb only.
            (let ((pos (plist-get (plist-get (plist-get card :on_long_tap)
                                             :args)
                                  :pos)))
              (should (jetpacs-buffer-exposed-p (buffer-name buf) pos
                                                "sections.menu"))
              (should-not (jetpacs-buffer-exposed-p (buffer-name buf) pos
                                                    "emacs.buffer.act")))
            (should (jetpacs-check-node-types
                     (vconcat nodes)
                     (append (plist-get (plist-get jetpacs-sections-test--full
                                                   :app)
                                        :node_types)
                             nil)
                     "app"))))))))

(ert-deftest jetpacs-sections-render-degrades-to-core ()
  "SPEC 16.2: `collapsible' and `rich_text' are OPTIONAL."
  (jetpacs-sections-test--with-client (:profiles jetpacs-sections-test--core)
    (let* ((buf (jetpacs-sections-test--buffer))
           (root (jetpacs-sections-test--tree buf)))
      (with-current-buffer buf
        (let ((nodes (jetpacs-sections--emit root (buffer-name buf)
                                             (cons 500 nil))))
          (should (jetpacs-check-node-types
                   (vconcat nodes)
                   (append (plist-get (plist-get jetpacs-sections-test--core
                                                 :app)
                                      :node_types)
                           nil)
                   "app")))))))

(ert-deftest jetpacs-sections-body-budget ()
  "The line budget elides bodies with a note rather than over-emitting."
  (jetpacs-sections-test--with-client ()
    (with-current-buffer (get-buffer-create "*jc3-big*")
      (erase-buffer)
      (dotimes (i 20) (insert (format "line %d\n" i)))
      (let* ((budget (cons 3 nil))
             (nodes (jetpacs-sections--body-lines (point-min) (point-max)
                                                  (buffer-name) budget)))
        (should (<= (length nodes) 4))
        (should (string-match-p "more line"
                                (plist-get (car (last nodes)) :text)))))))

;;;; Actions

(ert-deftest jetpacs-sections-visit-statuses ()
  (jetpacs-sections-test--with-client ()
    (let* ((buf (jetpacs-sections-test--buffer))
           (name (buffer-name buf))
           (handler (gethash "sections.visit" jetpacs-action-handlers)))
      ;; Not a section buffer -> rejected (magit-section is absent, so the
      ;; real predicate refuses; that is the honest 23.1 answer).
      (should (eq (funcall handler (list :buffer name :pos 1)
                          '(:surface "app:demo"))
                  'rejected))
      (should (eq (funcall handler '(:buffer "*nope*" :pos 1)
                          '(:surface "app:demo"))
                  'rejected))
      (should (eq (funcall handler (list :buffer name :pos "x")
                          '(:surface "app:demo"))
                  'rejected)))))

(ert-deftest jetpacs-sections-menu-never-blocks ()
  "Decision D2: the menu must NOT call `completing-read' in the handler.
The poc did, which blocks the jsonrpc dispatch extent."
  ;; The source must not reach for a blocking prompt at all.
  (let ((src (with-temp-buffer
               (insert-file-contents jetpacs-sections-test--source)
               (buffer-string))))
    (should-not (string-match-p "(completing-read " src))
    (should-not (string-match-p "(read-string " src))
    (should (string-match-p "ebp-client-dialog-show" src)))
  ;; And without the dialog capability it refuses rather than hanging.
  (jetpacs-sections-test--with-client ()
    (should (eq (funcall (gethash "sections.menu" jetpacs-action-handlers)
                         '(:buffer "*nope*" :pos 1) '(:surface "app:demo"))
                'rejected))))

;;;; JC-3c comint

(defun jetpacs-sections-test--comint ()
  "A comint buffer with no live process (the offline half)."
  (with-current-buffer (get-buffer-create "*jc3-comint*")
    (erase-buffer)
    (comint-mode)
    (let ((inhibit-read-only t))
      (insert "$ echo hi\nhi\n$ \n"))
    (current-buffer)))

(ert-deftest jetpacs-comint-render-structure ()
  "Status row + transcript tail; no input row without a live process."
  (jetpacs-sections-test--with-client ()
    (let* ((buf (jetpacs-sections-test--comint))
           (nodes (jetpacs-comint-render buf))
           (kinds (jetpacs--collect-node-types (vconcat nodes) '())))
      (should (equal (plist-get (car nodes) :t) "row"))
      (should (string-match-p "no live process"
                             (format "%s" (jetpacs-node->canonical-json
                                           (vconcat nodes)))))
      ;; No live process -> no input row and no interrupt button.
      (should-not (member "text_input" kinds))
      (should (jetpacs-check-node-types
               (vconcat nodes)
               (append (plist-get (plist-get jetpacs-sections-test--full :app)
                                  :node_types)
                       nil)
               "app")))))

(ert-deftest jetpacs-comint-action-statuses ()
  "SPEC 14.4/23.1: both actions gate on a live comint process."
  (jetpacs-sections-test--with-client ()
    (let ((send (gethash "comint.send" jetpacs-action-handlers))
          (interrupt (gethash "comint.interrupt" jetpacs-action-handlers))
          (params '(:surface "app:demo")))
      (jetpacs-sections-test--comint)
      ;; Unknown buffer, wrong mode, and no live process all reject.
      (should (eq (funcall send '(:buffer "*nope*" :value "x") params)
                  'rejected))
      (should (eq (funcall send '(:buffer "*jc3-comint*" :value "x") params)
                  'rejected))
      (should (eq (funcall interrupt '(:buffer "*jc3-comint*") params)
                  'rejected))
      ;; A non-string value is never sent.
      (should (eq (funcall send '(:buffer "*jc3-comint*" :value 42) params)
                  'rejected)))))

(ert-deftest jetpacs-comint-send-reads-injected-value ()
  "SPEC 14.3: `on_submit' injects the submitted text as `value' in ARGS
\(only a PASSWORD submission uses `fields'), so the descriptor carries no
value member and the handler reads args."
  (jetpacs-sections-test--with-client ()
    (let* ((nodes (jetpacs-comint-render (jetpacs-sections-test--comint)))
           (json (jetpacs-node->canonical-json (vconcat nodes))))
      ;; The rendered input (absent here, no process) would carry on_submit
      ;; with no authored value; assert the render is at least clean JSON.
      (should (stringp json)))
    ;; The handler's contract: value comes from args.
    (should (eq (funcall (gethash "comint.send" jetpacs-action-handlers)
                         '(:buffer "*jc3-comint*") '(:surface "app:demo"))
                'rejected))))

;; --- Regression: the three P1s found reviewing JC-3a ------------------------

(defvar jetpacs-sections-test--ran nil)
(defun jetpacs-sections-test--danger () (interactive)
  (setq jetpacs-sections-test--ran 'danger))
(defun jetpacs-sections-test--safe () (interactive)
  (setq jetpacs-sections-test--ran 'safe))

(ert-deftest jetpacs-sections-header-tap-leaves-no-act-exposure ()
  "Stripping a header tap must not leave its position exposed (SPEC 23.1).
The Tier-0 span builder exposes every actionable position for
`emacs.buffer.act'.  This substrate strips the tap on headers, so a
surviving record would let the phone synthesize `emacs.buffer.act' there
and reach `jetpacs-buffer-invoke-at' UNSHIMMED — a desktop window it
cannot see.  The keymap is on the HEADER line here on purpose: the
original fixture put it only on the body, so no record was ever written
and the leak was invisible."
  (with-temp-buffer
    (let ((km (make-sparse-keymap)))
      (define-key km (kbd "RET") #'jetpacs-sections-test--safe)
      (insert "Actionable heading\n")
      (put-text-property (point-min) 19 'keymap km))
    (rename-buffer "*jc3-hdr*" t)
    (jetpacs-buffer-forget-exposed)
    (jetpacs-sections--strip-taps
     (jetpacs-sections--spans (point-min) 19 (buffer-name)))
    (should-not (jetpacs-buffer-exposed-p
                 (buffer-name) 1 "emacs.buffer.act"))))

(ert-deftest jetpacs-sections-retarget-exposes-only-the-new-verb ()
  "A retargeted tap authorizes `sections.visit' and NOTHING else.
Both verbs exposed would leave the unshimmed path reachable alongside the
shimmed one, which defeats the point of retargeting."
  (with-temp-buffer
    (let ((km (make-sparse-keymap)))
      (define-key km (kbd "RET") #'jetpacs-sections-test--safe)
      (insert "Body row\n")
      (put-text-property (point-min) 9 'keymap km))
    (rename-buffer "*jc3-retarget*" t)
    (jetpacs-buffer-forget-exposed)
    (jetpacs-sections--retarget-taps
     (jetpacs-sections--spans (point-min) 9 (buffer-name)) (buffer-name))
    (should (jetpacs-buffer-exposed-p (buffer-name) 1 "sections.visit"))
    (should-not (jetpacs-buffer-exposed-p
                 (buffer-name) 1 "emacs.buffer.act"))))

(ert-deftest jetpacs-sections-replay-key-refuses-wire-invented-keys ()
  "A key off the wire that is not a CURRENT candidate must not run.
`--replay-key' receives the dialog's submitted value, so SPEC 23.2's ban
on handing unvalidated names to an ambient dispatcher applies: a bare
`execute-kbd-macro' would let a Companion send magit's `x' (reset) or
`C-x C-f'.  Here `x' is bound in the buffer but never offered."
  (with-temp-buffer
    (insert "line\n")
    (let ((km (make-sparse-keymap)))
      (define-key km (kbd "x") #'jetpacs-sections-test--danger)
      (use-local-map km))
    (setq jetpacs-sections-test--ran nil)
    (cl-letf (((symbol-function 'jetpacs-sections--menu-candidates)
               (lambda (_pos) '(("Safe" . "RET")))))
      (jetpacs-sections--replay-key (current-buffer) 1 "x" nil))
    (should-not jetpacs-sections-test--ran)))

(ert-deftest jetpacs-sections-tolerates-nil-markers ()
  "A section mid-`magit-refresh' has an unset `end'; that must not signal.
Any push racing a refresh would otherwise take the whole surface down
instead of costing one section its body."
  (let ((sec (record 'jc3-sec)))
    (cl-letf (((symbol-function 'jetpacs-sections--pos)
               (lambda (_s slot) (pcase slot ('start 1) ('content 2)
                                        (_ nil))))
              ((symbol-function 'jetpacs-sections--hidden-p) (lambda (_s) nil))
              ((symbol-function 'jetpacs-sections--slot) (lambda (_s _sl) nil))
              ((symbol-function 'jetpacs-sections--id) (lambda (_s) "id")))
      (with-temp-buffer
        (insert "a\n")
        (rename-buffer "*jc3-nil*" t)
        (should (jetpacs-sections--emit sec (buffer-name) (list 10)))))))

(ert-deftest jetpacs-feature-advertised-p-offline-and-gated ()
  "The 22.4 feature twin: absent from the profile means NOT advertised."
  (should (jetpacs-feature-advertised-p "image.data"))   ; offline: richer form
  ;; A real struct, not a fake record: `ebp-client-profiles' is a
  ;; `cl-defstruct' accessor that indexes the record directly, so letf-ing
  ;; the symbol does not intercept the call site.
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jetpacs-sections-receipts"))))
    (setf (ebp-client-state client) 'ready
          (ebp-client-profiles client) '(:app (:features ["image.https"])))
    (cl-letf (((symbol-function 'jetpacs-client) (lambda () client)))
      (should (jetpacs-feature-advertised-p "image.https"))
      (should-not (jetpacs-feature-advertised-p "image.data")))))

;; --- Phase C conformance (C1/C2/C4/C5/C7/C9) --------------------------------

(defun jetpacs-sections-test--fake-sec (start content end &optional ident)
  "A stand-in section object; IDENT is what `magit-section-ident' returns."
  (record 'jc3-sec start content end ident))

(defmacro jetpacs-sections-test--with-fake-tree (&rest body)
  "Run BODY with the section accessors reading `jetpacs-sections-test--fake-sec'."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'jetpacs-sections--pos)
              (lambda (s slot) (pcase slot ('start (aref s 1))
                                      ('content (aref s 2)) ('end (aref s 3)))))
             ((symbol-function 'jetpacs-sections--slot)
              (lambda (_s _sl) nil))
             ((symbol-function 'jetpacs-sections--hidden-p) (lambda (_s) nil))
             ((symbol-function 'magit-section-ident) (lambda (s) (aref s 4))))
     ,@body))

(ert-deftest jetpacs-sections-ids-are-unique-per-render ()
  "SPEC 16.1: a duplicate node id is `1201' for the WHOLE update.
Two magit sections really can collide — the ident repeats across taxy and
forge groupings, and two sections sharing a `start' marker produce the
same positional fallback."
  (jetpacs-sections-test--with-fake-tree
    (let ((jetpacs-sections--ids (make-hash-table :test #'equal))
          (a (jetpacs-sections-test--fake-sec 1 2 9 '(same)))
          (b (jetpacs-sections-test--fake-sec 1 2 9 '(same))))
      (let ((id-a (jetpacs-sections--id a))
            (id-b (jetpacs-sections--id b)))
        (should-not (equal id-a id-b))
        ;; The FIRST claimant keeps the stable id (and its fold state).
        (should (equal id-a (md5 (format "%S" '(same)))))
        (should (jetpacs--identifier-p id-b))))
    ;; ...and a synthesized suffix never collides with a real id either.
    (let ((jetpacs-sections--ids (make-hash-table :test #'equal)))
      (puthash "x" 1 jetpacs-sections--ids)
      (puthash "x-1" t jetpacs-sections--ids)
      (cl-letf (((symbol-function 'magit-section-ident)
                 (lambda (_s) (error "no ident"))))
        ;; Falls back to "sec-POS"; force the base to be the taken "x".
        (should (jetpacs--identifier-p
                 (let ((jetpacs-sections--ids jetpacs-sections--ids))
                   (jetpacs-sections--id
                    (jetpacs-sections-test--fake-sec 1 2 9 nil)))))))))

(ert-deftest jetpacs-sections-ids-survive-outside-a-render ()
  "With no per-render table bound, ids pass through unsuffixed."
  (jetpacs-sections-test--with-fake-tree
    (let ((jetpacs-sections--ids nil)
          (a (jetpacs-sections-test--fake-sec 1 2 9 '(one))))
      (should (equal (jetpacs-sections--id a) (jetpacs-sections--id a))))))

(ert-deftest jetpacs-sections-card-cap-bounds-node-count ()
  "SPEC 4.5: the line budget does not bound CARDS.
A `magit-log' is thousands of sections whose bodies are one line each, so
the line budget is never reached while the node count sails past the
ceiling and the whole push is refused.  Past the cap the walk stops and
latches exactly one note."
  (let ((jetpacs-sections-max-sections 3)
        (jetpacs-sections--cards 0)
        (jetpacs-sections--ids (make-hash-table :test #'equal)))
    (jetpacs-sections-test--with-fake-tree
      (with-temp-buffer
        (insert "a\nb\nc\nd\ne\nf\n")
        (rename-buffer "*jc3-cap*" t)
        (let ((notes 0))
          (dotimes (i 6)
            (let ((nodes (jetpacs-sections--emit
                          (jetpacs-sections-test--fake-sec 1 2 6 (list i))
                          (buffer-name) (cons 100 nil))))
              (dolist (n nodes)
                (when (equal (plist-get n :style) "caption")
                  (cl-incf notes)))))
          ;; Three cards, then ONE note, then silence.
          (should (= notes 1)))))))

(ert-deftest jetpacs-sections-core-degrade-exposes-no-menu ()
  "SPEC 23.1: the Core path emits no long-tap, so it must authorize none.
An exposure record for an affordance absent from the document is an
authorization the phone can spend on something it was never offered."
  (jetpacs-sections-test--with-client
      (:profiles '(:app (:node_types ["text" "row" "column" "box" "spacer"
                                      "divider" "button" "text_input"]
                         :builtins [] :features [])))
    (jetpacs-buffer-forget-exposed)
    (jetpacs-sections-test--with-fake-tree
      (let ((header (jetpacs-text "h")))
        (jetpacs-sections--card
         (jetpacs-sections-test--fake-sec 1 2 9 '(x)) "*jc3-core*" 1
         header (list (jetpacs-text "body")))
        (should-not
         (jetpacs-buffer-exposed-p "*jc3-core*" 1 "sections.menu"))))))

(ert-deftest jetpacs-sections-core-degrade-hides-folded-bodies ()
  "C13: with no `collapsible', a FOLDED section renders header-only.
Showing its body would put content on the phone that the user has
explicitly collapsed in Emacs — and on the Core path there is no fold
affordance to re-collapse it with."
  (jetpacs-sections-test--with-client
      (:profiles '(:app (:node_types ["text" "row" "column" "box" "spacer"
                                      "divider" "button" "text_input"]
                         :builtins [] :features [])))
    (let ((header (jetpacs-text "h"))
          (body (list (jetpacs-text "secret body"))))
      (cl-letf (((symbol-function 'jetpacs-sections--hidden-p) (lambda (_s) t)))
        (let ((node (jetpacs-sections--card
                     (jetpacs-sections-test--fake-sec 1 2 9 '(x))
                     "*jc3-fold*" 1 header body)))
          (should (equal node header))
          (should-not (string-match-p
                       "secret body"
                       (jetpacs-node->canonical-json node)))))
      ;; ...and an UNfolded one still shows its content.
      (cl-letf (((symbol-function 'jetpacs-sections--hidden-p) (lambda (_s) nil)))
        (should (string-match-p
                 "secret body"
                 (jetpacs-node->canonical-json
                  (jetpacs-sections--card
                   (jetpacs-sections-test--fake-sec 1 2 9 '(x))
                   "*jc3-fold*" 1 header body))))))))

(ert-deftest jetpacs-sections-elision-note-is-latched ()
  "C3: one elision caption per RENDER, not per remaining section.
The spent-budget branch is reached once per section, so a large
`magit-status' otherwise trails a caption after every one of them."
  (with-temp-buffer
    (insert "a\nb\nc\nd\n")
    (rename-buffer "*jc3-elide*" t)
    (let ((budget (cons 0 nil))
          (notes 0))
      (dotimes (_ 3)
        (dolist (n (jetpacs-sections--body-lines
                    (point-min) (point-max) (buffer-name) budget))
          (when (equal (plist-get n :style) "caption")
            (cl-incf notes))))
      (should (= notes 1)))))

(ert-deftest jetpacs-sections-menu-mode-keys-are-allowlisted ()
  "C16: the section's OWN map is offered whole; the MODE map is not.

A mode map is the buffer's entire user interface — scanning magit-status
wholesale yielded 60 candidates, which is magit's keymap, not this
section's verbs, and useless as a phone long-press.  So mode-level keys
are an allowlist while the nearer, genuinely per-section map is offered
in full."
  (with-temp-buffer
    (insert "row\n")
    (let ((mode-map (make-sparse-keymap))
          (near-map (make-sparse-keymap))
          (jetpacs-sections-menu-mode-keys '("s")))
      (define-key mode-map (kbd "s") #'jetpacs-sections-test--safe)
      (define-key mode-map (kbd "z") #'jetpacs-sections-test--safe)
      (define-key near-map (kbd "s") #'jetpacs-sections-test--danger)
      (define-key near-map (kbd "q") #'jetpacs-sections-test--safe)
      (use-local-map mode-map)
      (put-text-property (point-min) 4 'keymap near-map)
      (let ((cands (jetpacs-sections--menu-candidates (point-min))))
        ;; Allowlisted mode key: present.  Non-allowlisted: absent.
        (should (rassoc "s" cands))
        (should-not (rassoc "z" cands))
        ;; The nearer map is section-specific, so it is NOT allowlisted.
        (should (rassoc "q" cands))
        ;; `s' resolves once, from the NEARER map.
        (should (= 1 (cl-count "s" cands :key #'cdr :test #'equal)))
        (should (rassoc "TAB" cands))))))

(ert-deftest jetpacs-sections-menu-is-capped ()
  "A future keymap must degrade to a usable dialog, not a wall."
  (with-temp-buffer
    (insert "row\n")
    (let ((km (make-sparse-keymap))
          (jetpacs-sections-menu-max 5))
      (dolist (c '(?a ?b ?d ?e ?f ?g ?h ?i ?j))
        (define-key km (vector c) #'jetpacs-sections-test--safe))
      (put-text-property (point-min) 4 'keymap km)
      (should (= 5 (length (jetpacs-sections--menu-candidates
                            (point-min))))))))

(ert-deftest jetpacs-sections-menu-refuses-denylisted ()
  "A denylisted command is not offered even when bound AND callable.
Naming a real magit command here would prove nothing: magit is not
loaded in the suite, so `commandp' would reject it before the denylist
was ever consulted — which is exactly how the first version of this test
passed vacuously."
  (with-temp-buffer
    (insert "row\n")
    (let ((km (make-sparse-keymap))
          (jetpacs-sections-menu-denylist
           (cons 'jetpacs-sections-test--danger
                 jetpacs-sections-menu-denylist)))
      (define-key km (kbd "k") #'jetpacs-sections-test--danger)
      (define-key km (kbd "j") #'jetpacs-sections-test--safe)
      (put-text-property (point-min) 4 'keymap km)
      (let ((cands (jetpacs-sections--menu-candidates (point-min))))
        (should (rassoc "j" cands))          ; the control
        (should-not (rassoc "k" cands))))))

(provide 'jetpacs-sections-test)
;;; jetpacs-sections-test.el ends here
