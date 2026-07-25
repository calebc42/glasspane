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

(provide 'jetpacs-sections-test)
;;; jetpacs-sections-test.el ends here
