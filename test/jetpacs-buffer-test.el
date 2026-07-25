;;; jetpacs-buffer-test.el --- JC-1 Tier-0 renderer exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JC-1 exit gate (docs/PLAN-jetpacs-consumers.md): a fontified
;; fixture renders to a byte-asserted golden (test/goldens/renderers.golden
;; — regenerate by evaluating `jetpacs-buffer-test--write-golden' after a
;; reviewed rendering change); the tree passes the reference profile; the
;; welcome span/byte budgets truncate rather than over-emit (plan 2.5-5);
;; and the two tap actions honor decision D2 (status now, effect deferred).

;;; Code:

(require 'ert)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-buffer)

(defconst jetpacs-buffer-test--golden
  (expand-file-name "goldens/renderers.golden"
                    (file-name-directory
                     (or load-file-name buffer-file-name)))
  "The byte-asserted rendering golden.")

(defun jetpacs-buffer-test--fixture ()
  "Build the deterministic fixture buffer and return it.
Covers: a plain line, format-6 span styling (bold weight, exact hex
color, underline), TAB expansion, a blank line, and a tappable button."
  (with-current-buffer (get-buffer-create "*jc1-fixture*")
    (fundamental-mode)
    (erase-buffer)
    (insert "Hello world\n")
    (insert (concat (propertize "bold" 'face '(:weight bold))
                    " and "
                    (propertize "red" 'face '(:foreground "red"))
                    " "
                    (propertize "ul" 'face '(:underline t))
                    "\n"))
    (insert "a\tb\n")
    (insert "\n")
    (insert-text-button "press me" 'action #'ignore)
    (insert "\n")
    (current-buffer)))

(defun jetpacs-buffer-test--render-fixture ()
  "The fixture rendered to canonical JSON."
  (jetpacs-node->canonical-json
   (vconcat (jetpacs-buffer-render (jetpacs-buffer-test--fixture)))))

(defun jetpacs-buffer-test--write-golden ()
  "Regenerate the golden from the fixture (run after a reviewed change)."
  (with-temp-file jetpacs-buffer-test--golden
    (insert (jetpacs-buffer-test--render-fixture))))

(defmacro jetpacs-buffer-test--with-client (limits &rest body)
  "Attach a stub client whose welcome LIMITS bound the render, run BODY."
  (declare (indent 1))
  `(let ((client (ebp-client-create
                  :receipt-file (make-temp-file "jc1-receipts"))))
     (setf (ebp-client-limits client) ,limits)
     (unwind-protect
         (progn (jetpacs-attach client) ,@body)
       (jetpacs-detach))))

(ert-deftest jetpacs-buffer-golden ()
  "The fixture renders byte-identically to the reviewed golden."
  (should (file-readable-p jetpacs-buffer-test--golden))
  (should (equal (jetpacs-buffer-test--render-fixture)
                 (with-temp-buffer
                   (insert-file-contents jetpacs-buffer-test--golden)
                   (buffer-string)))))

(ert-deftest jetpacs-buffer-passes-reference-profile ()
  "The rendered tree uses only reference app-profile node types."
  (should (jetpacs-check-profile
           (vconcat (jetpacs-buffer-render (jetpacs-buffer-test--fixture)))
           'app)))

(defun jetpacs-buffer-test--count-spans (nodes)
  "Total spans across every rich_text node in NODES."
  (apply #'+ (mapcar (lambda (n) (length (append (plist-get n :spans) nil)))
                     nodes)))

(ert-deftest jetpacs-buffer-span-budget-is-aggregate ()
  "SPEC 4.5: `max_rich_spans' is an AGGREGATE count across one
SurfaceSpec, not a per-node cap.  Many small lines, each well under the
limit, must still not sail past it in total."
  (jetpacs-buffer-test--with-client '(:max_rich_spans 10)
    (with-current-buffer (get-buffer-create "*jc1-aggregate*")
      (fundamental-mode)
      (erase-buffer)
      ;; 30 lines x 1 span each = 30 spans aggregate, far over the 10 cap,
      ;; yet every individual line is within it.
      (dotimes (i 30) (insert (format "line %d\n" i)))
      (let* ((nodes (jetpacs-buffer-render (current-buffer)))
             (line-nodes (seq-filter
                          (lambda (n) (equal (plist-get n :t) "rich_text"))
                          nodes)))
        (should (<= (jetpacs-buffer-test--count-spans line-nodes) 10))
        (should (< (length line-nodes) 30))
        (should (string-match-p "truncated"
                                (plist-get (car (last nodes)) :text)))))))

(ert-deftest jetpacs-buffer-span-cap ()
  "A single line over the whole budget truncates with an ellipsis span."
  (jetpacs-buffer-test--with-client '(:max_rich_spans 4)
    (with-current-buffer (get-buffer-create "*jc1-spans*")
      (fundamental-mode)
      (erase-buffer)
      ;; Six differently-styled runs on one line -> six spans unbounded.
      (dotimes (i 6)
        (insert (propertize (format "run%d " i)
                            'face (if (cl-evenp i) '(:weight bold)
                                    '(:underline t)))))
      (insert "\n")
      (let* ((nodes (jetpacs-buffer-render (current-buffer)))
             (spans (append (plist-get (car nodes) :spans) nil)))
        ;; The line, then the truncation caption the budget stop appends.
        (should (= (length nodes) 2))
        (should (equal (plist-get (nth 1 nodes) :t) "text"))
        ;; Exactly the budget, ellipsis last — never budget+1.
        (should (= (length spans) 4))
        (should (equal (plist-get (car (last spans)) :text) "…"))))))

(ert-deftest jetpacs-buffer-byte-budget ()
  "Plan 2.5-5: the render stops before crowding max_frame_bytes and
appends a visible truncation note instead of over-emitting."
  (jetpacs-buffer-test--with-client '(:max_frame_bytes 3100) ; budget 1052
    (with-current-buffer (get-buffer-create "*jc1-bytes*")
      (fundamental-mode)
      (erase-buffer)
      (dotimes (i 40)
        (insert (format "line %02d: %s\n" i (make-string 60 ?x))))
      (let* ((nodes (jetpacs-buffer-render (current-buffer)))
             (last-node (car (last nodes)))
             (line-nodes (butlast nodes))
             (total (apply #'+ (mapcar #'jetpacs-buffer--node-bytes
                                       line-nodes))))
        (should (< (length nodes) 40))
        (should (equal (plist-get last-node :t) "text"))
        (should (string-match-p "truncated" (plist-get last-node :text)))
        (should (<= total 1052))))))

(ert-deftest jetpacs-buffer-degrades-without-rich-text ()
  "SPEC 16.2: `rich_text' is OPTIONAL, not Core.  Against a Companion
that advertises only the Core Node Set the renderer must emit Core
`text' lines — not an unadvertised type the sender gate would refuse."
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jc1-core"))))
    (setf (ebp-client-limits client) '(:max_frame_bytes 4194304)
          (ebp-client-profiles client)
          '(:app (:node_types ["text" "row" "column" "box" "spacer"
                               "divider" "button" "text_input"]
                  :builtins [] :features [])))
    (unwind-protect
        (progn
          (jetpacs-attach client)
          (with-current-buffer (get-buffer-create "*jc1-core*")
            (fundamental-mode)
            (erase-buffer)
            (insert (propertize "styled" 'face '(:weight bold)))
            (insert " plain\n")
            (let* ((nodes (jetpacs-buffer-render (current-buffer)))
                   (node (car nodes)))
              (should (equal (plist-get node :t) "text"))
              (should (equal (plist-get node :text) "styled plain"))
              ;; The whole tree must clear the live Core-only gate.
              (should (jetpacs-check-node-types
                       (vconcat nodes)
                       '("text" "row" "column" "box" "spacer" "divider"
                         "button" "text_input")
                       "app")))))
      (jetpacs-detach))))

(ert-deftest jetpacs-buffer-unbounded-without-client ()
  "With no client attached, only the line cap applies (offline render)."
  (jetpacs-detach)
  (with-current-buffer (get-buffer-create "*jc1-free*")
    (fundamental-mode)
    (erase-buffer)
    (dotimes (i 6)
      (insert (propertize (format "r%d" i)
                          'face (if (cl-evenp i) '(:weight bold)
                                  '(:underline t)))))
    (insert "\n")
    (let ((spans (append (plist-get (car (jetpacs-buffer-render
                                          (current-buffer)))
                                    :spans)
                         nil)))
      (should (= (length spans) 6)))))

(ert-deftest jetpacs-buffer-line-cap-note ()
  (let ((jetpacs-buffer-max-lines 3))
    (with-current-buffer (get-buffer-create "*jc1-cap*")
      (fundamental-mode)
      (erase-buffer)
      (dotimes (i 10) (insert (format "l%d\n" i)))
      (let ((nodes (jetpacs-buffer-render (current-buffer))))
        (should (= (length nodes) 4))    ; 3 lines + the caption
        (should (string-match-p "more line"
                                (plist-get (car (last nodes)) :text)))))))

(ert-deftest jetpacs-buffer-render-tail ()
  (with-current-buffer (get-buffer-create "*jc1-tail*")
    (fundamental-mode)
    (erase-buffer)
    (dotimes (i 10) (insert (format "l%d\n" i)))
    (let ((nodes (jetpacs-buffer-render-tail (current-buffer) 2)))
      (should (string-match-p "earlier line"
                              (plist-get (car nodes) :text)))
      (should (equal (plist-get (car (last nodes)) :t) "rich_text")))))

(ert-deftest jetpacs-buffer-skin-dispatch ()
  "Tier-1 skins override by derived mode; unregistered modes fall through."
  (let ((jetpacs-render-buffer-functions nil))
    (jetpacs-render-buffer-register
     'special-mode (lambda (_buf) (list (jetpacs-text "skinned"))))
    (with-current-buffer (get-buffer-create "*jc1-skin*")
      (special-mode)
      (should (equal (plist-get (car (jetpacs-render-buffer
                                      (current-buffer)))
                     :text)
                     "skinned")))
    (with-current-buffer (get-buffer-create "*jc1-plain*")
      (fundamental-mode)
      (erase-buffer)
      (insert "raw\n")
      (should (equal (plist-get (car (jetpacs-render-buffer
                                      (current-buffer)))
                     :t)
                     "rich_text")))))

(ert-deftest jetpacs-buffer-actions-honor-d2 ()
  "The tap actions validate and answer now, deferring the effect
\(decision D2): rejected for an unresolvable buffer; accepted with the
effect and refresh running only from the captured continuation."
  (let ((act (gethash "emacs.buffer.act" jetpacs-action-handlers))
        (fold (gethash "jetpacs.buffer.fold" jetpacs-action-handlers)))
    (should (functionp act))
    (should (functionp fold))
    ;; Unresolvable args are terminal (SPEC 14.1): no continuation.
    (should (eq (funcall act '(:buffer "*no such*" :pos 1) '()) 'rejected))
    (should (eq (funcall fold '(:buffer "*no such*" :pos 1) '()) 'rejected))
    ;; A valid tap answers accepted immediately; the effect + refresh run
    ;; only when the deferred continuation fires.
    (let (deferred pressed refreshed)
      (with-current-buffer (get-buffer-create "*jc1-act*")
        (fundamental-mode)
        (erase-buffer)
        (insert-text-button "go" 'action (lambda (_) (setq pressed t)))
        (insert "\n"))
      (cl-letf (((symbol-function 'run-at-time)
                 (lambda (_time _repeat fn &rest _) (push fn deferred)))
                (jetpacs-buffer-refresh-function
                 (lambda (surface) (setq refreshed surface))))
        (should (eq (funcall act '(:buffer "*jc1-act*" :pos 1)
                            '(:surface "app:demo"))
                    'accepted))
        (should (= (length deferred) 1))
        (should-not pressed)
        (should-not refreshed)
        (funcall (car deferred))
        (should pressed)
        (should (equal refreshed "app:demo"))))))

(provide 'jetpacs-buffer-test)
;;; jetpacs-buffer-test.el ends here
