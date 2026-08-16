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
(require 'jetpacs-shell)
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
             (total (apply #'+ (mapcar #'jetpacs-buffer-node-bytes
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

(ert-deftest jetpacs-buffer-non-scalar-bytes-are-serializable ()
  "SPEC 4.1: every emitted string must be Unicode scalar values.
Emacs holds an undecodable octet as a raw-byte char (#x3FFF80..) which
`json-serialize' rejects outright, so any non-UTF-8 buffer would
otherwise take down the whole render — and the Core-`text' fallback
hits the same serializer, so it is no escape."
  (with-current-buffer (get-buffer-create "*jc1-bytes-raw*")
    (fundamental-mode)
    (erase-buffer)
    (insert "caf" (string-to-multibyte "\310\311") "\n")
    ;; Precondition: the fixture really does hold non-scalar chars.
    (should (cl-some (lambda (c) (>= c #x3FFF80))
                     (append (buffer-string) nil)))
    (let* ((nodes (jetpacs-buffer-render (current-buffer)))
           (span (aref (plist-get (car nodes) :spans) 0)))
      ;; The guarantee: the whole tree serializes.
      (should (jetpacs-node->canonical-json (vconcat nodes)))
      (should (equal (plist-get span :text) "caf\uFFFD\uFFFD")))))

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
  "SPEC 14.4 + decision D2: rejected for an unresolvable buffer;
`accepted' only once the effect has ACTUALLY RUN (a volatile-callback
accept is explicitly non-conforming), with only the re-push deferred."
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
        (insert "\n")
        ;; Render first: only offsets this Emacs actually emitted are
        ;; tappable (SPEC 23.1), and the button sits at pos 1.
        (jetpacs-buffer-render (current-buffer)))
      (cl-letf (((symbol-function 'run-at-time)
                 (lambda (_time _repeat fn &rest _) (push fn deferred)))
                (jetpacs-buffer-refresh-function
                 (lambda (surface) (setq refreshed surface))))
        (should (eq (funcall act '(:buffer "*jc1-act*" :pos 1)
                            '(:surface "app:demo"))
                    'accepted))
        ;; The effect ran BEFORE accepted was returned (SPEC 14.4)...
        (should pressed)
        ;; ...and only the re-push was deferred.
        (should (= (length deferred) 1))
        (should-not refreshed)
        (funcall (car deferred))
        (should (equal refreshed "app:demo"))))))

(ert-deftest jetpacs-buffer-tap-must-have-been-rendered ()
  "SPEC 23.1: a tap naming a buffer/offset this Emacs never emitted is
outside the trust boundary and is refused — otherwise a Companion could
drive any command in any live buffer (Customize's [Apply and Save], a
package-menu install button, an eww link) that the user never sent."
  (with-current-buffer (get-buffer-create "*jc1-unexposed*")
    (fundamental-mode)
    (erase-buffer)
    (insert-text-button "danger" 'action #'ignore)
    (insert "\n"))
  (jetpacs-buffer-forget-exposed)
  (let ((act (gethash "emacs.buffer.act" jetpacs-action-handlers)))
    ;; Never rendered -> refused even though the button really is there.
    (should (eq (funcall act '(:buffer "*jc1-unexposed*" :pos 1)
                         '(:surface "app:demo"))
                'rejected))
    ;; After a render the same tap is honored...
    (jetpacs-buffer-render "*jc1-unexposed*")
    (should (jetpacs-buffer-exposed-p "*jc1-unexposed*" 1))
    ;; ...but an offset the render did not expose still is not.
    (should-not (jetpacs-buffer-exposed-p "*jc1-unexposed*" 999))
    (should (eq (funcall act '(:buffer "*jc1-unexposed*" :pos 999)
                         '(:surface "app:demo"))
                'rejected))))

(ert-deftest jetpacs-buffer-tap-stale-revision ()
  "SPEC 14.5: an event created against a snapshot below the surface's
live floor named an offset that may have moved -> `stale', which the
Companion may re-present, not terminal `rejected'."
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jc1-stale"))))
    (unwind-protect
        (progn
          (jetpacs-attach client)
          ;; Staleness is measured against the CONFIRMED-applied revision.
          (jetpacs-shell--confirm-applied "app:demo" 9 "applied" nil)
          (with-current-buffer (get-buffer-create "*jc1-stale*")
            (fundamental-mode)
            (erase-buffer)
            (insert-text-button "go" 'action #'ignore)
            (insert "\n")
            (jetpacs-buffer-render (current-buffer)))
          (should (eq (funcall (gethash "emacs.buffer.act"
                                        jetpacs-action-handlers)
                               '(:buffer "*jc1-stale*" :pos 1)
                               '(:surface "app:demo" :revision_seen 3))
                      'stale)))
      (jetpacs-detach))))

;;;; JA-2c: the thunk primitive + the display-buffer shim (B4)

(ert-deftest jetpacs-buffer-funcall-shimmed-captures-switch ()
  (with-current-buffer (get-buffer-create "*nav-origin*")
    (let ((ret (jetpacs-buffer-funcall-shimmed
                (lambda () (switch-to-buffer (get-buffer-create "*nav-dest*"))))))
      (should (eq (car ret) (get-buffer "*nav-dest*")))
      (should (integerp (cdr ret))))))

(ert-deftest jetpacs-buffer-funcall-shimmed-display-buffer-is-record-only ()
  (with-current-buffer (get-buffer-create "*nav-origin*")
    (let (seen-cur win)
      (let ((ret (jetpacs-buffer-funcall-shimmed
                  (lambda ()
                    (setq win (display-buffer (get-buffer-create "*nav-disp*")))
                    (setq seen-cur (current-buffer))
                    nil))))
        ;; Recorded, not selected: precedence (b) fires, the thunk's own
        ;; current buffer never moved, and the shim returned a live window.
        (should (eq (car ret) (get-buffer "*nav-disp*")))
        (should (eq seen-cur (get-buffer "*nav-origin*")))
        (should (window-live-p win))))))

(ert-deftest jetpacs-buffer-funcall-shimmed-return-value-fallback ()
  (get-buffer-create "*nav-ret*")
  (with-current-buffer (get-buffer-create "*nav-origin*")
    (should (eq (car (jetpacs-buffer-funcall-shimmed (lambda () "*nav-ret*")))
                (get-buffer "*nav-ret*")))
    (should (eq (car (jetpacs-buffer-funcall-shimmed
                      (lambda () (get-buffer "*nav-ret*"))))
                (get-buffer "*nav-ret*")))))

(ert-deftest jetpacs-buffer-funcall-shimmed-plain-lambda-and-errors ()
  (with-current-buffer (get-buffer-create "*nav-origin*")
    ;; The B4 point: a plain non-interactive closure runs.
    (let ((ran nil))
      (jetpacs-buffer-funcall-shimmed (lambda () (setq ran t)))
      (should ran))
    (let (caught)
      (let ((ret (jetpacs-buffer-funcall-shimmed
                  (lambda () (error "boom"))
                  (lambda (err) (setq caught err)))))
        (should (eq (car caught) 'error))
        (should (eq (car ret) (get-buffer "*nav-origin*")))))))

(ert-deftest jetpacs-buffer-call-shimmed-display-buffer-capture ()
  (with-current-buffer (get-buffer-create "*nav-origin*")
    ;; The project-list-buffers shape: display only, never current.
    (let ((cmd (lambda () (interactive)
                 (display-buffer (get-buffer-create "*nav-cmd-disp*")))))
      (should (eq (car (jetpacs-buffer-call-shimmed cmd))
                  (get-buffer "*nav-cmd-disp*"))))
    ;; A current-buffer change WINS over a recorded display.
    (let ((cmd (lambda () (interactive)
                 (display-buffer (get-buffer-create "*nav-aux*"))
                 (switch-to-buffer (get-buffer-create "*nav-main*")))))
      (should (eq (car (jetpacs-buffer-call-shimmed cmd))
                  (get-buffer "*nav-main*"))))))

;;;; E4 — SPEC 23.1 exposure: commit point and authority scope

(defun jetpacs-buffer-test--fill (name lines)
  "A buffer NAME of LINES tappable button lines."
  (with-current-buffer (get-buffer-create name)
    (fundamental-mode)
    (erase-buffer)
    (dotimes (i lines)
      (insert-text-button (format "row-%d" i) 'action #'ignore)
      (insert "\n"))
    (current-buffer)))

(defun jetpacs-buffer-test--shipped-taps (nodes)
  "The (POS . ACTION) pairs NODES actually put on the wire, sorted."
  (let (out)
    (dolist (node nodes)
      (let ((spans (plist-get node :spans)))
        (when (or (vectorp spans) (consp spans))
          (mapc (lambda (s)
                  (when-let* ((d (plist-get s :on_tap))
                              (a (plist-get d :action))
                              (p (plist-get (plist-get d :args) :pos)))
                    (push (cons p a) out)))
                spans))))
    (sort out (lambda (x y) (< (car x) (car y))))))

(defun jetpacs-buffer-test--authorized-taps (name)
  "The (POS . ACTION) pairs currently authorized for NAME, sorted."
  (let (out)
    (maphash (lambda (pos verbs)
               (when (numberp pos)
                 (dolist (v verbs) (push (cons pos v) out))))
             (or (gethash name jetpacs-buffer-exposed)
                 (make-hash-table :test #'eql)))
    (sort out (lambda (x y) (< (car x) (car y))))))

(ert-deftest jetpacs-buffer-exposure-walks-transformed-line-controls ()
  "A transformed line authorizes nested span and trailing-icon taps."
  (let* ((name "*e4-transformed*")
         (fold (jetpacs-action "jetpacs.buffer.fold"
                               :args (list :buffer name :pos 1)))
         (actions (jetpacs-action "jetpacs.org.heading"
                                  :args (list :buffer name :pos 1)))
         (node (jetpacs-row
                (jetpacs-rich-text
                 (list (jetpacs-span "Heading" :on-tap fold)))
                (jetpacs-icon-button "more_vert" actions))))
    (jetpacs-buffer-forget-exposed name)
    (jetpacs-buffer--expose-node-taps node name)
    (should (jetpacs-buffer-exposed-p name 1 "jetpacs.buffer.fold"))
    (should (jetpacs-buffer-exposed-p name 1 "jetpacs.org.heading"))))

(ert-deftest jetpacs-buffer-exposure-waits-for-the-byte-budget ()
  "SPEC 23.1/4.5: a node the byte budget discards must leave its bindings
UNARMED.  Recording at span-build time authorized offsets that never
reached the wire, and `emacs.buffer.act' runs those bindings unshimmed.

The invariant is set equality — authorized == shipped — which is immune
to the trailing `… output truncated' caption node inflating a count."
  (let ((name "*e4-budget*"))
    (jetpacs-buffer-test--fill name 40)
    (jetpacs-buffer-forget-exposed)
    (let* ((jetpacs-buffer-budget (cons nil 400))
           (nodes (with-current-buffer name
                    (jetpacs-buffer--render-region
                     (point-min) (point-max) name))))
      ;; The walk really did discard a built node — otherwise vacuous.
      (should (< (length nodes) 40))
      (should (equal (jetpacs-buffer-test--shipped-taps nodes)
                     (jetpacs-buffer-test--authorized-taps name))))))

(ert-deftest jetpacs-buffer-exposure-matches-what-shipped-under-the-span-cap ()
  "A span the SPEC 4.5 cap replaced with the ellipsis took its `on_tap'
with it, so its offset must not stay authorized.  Uses a buffer whose
lines carry SEVERAL spans each, so the cap genuinely fires mid-line."
  (let ((name "*e4-cap*"))
    (with-current-buffer (get-buffer-create name)
      (fundamental-mode)
      (erase-buffer)
      ;; Several buttons per line => several tappable spans per line, so
      ;; an aggregate budget lands inside a line rather than between two.
      (dotimes (i 6)
        (dotimes (j 4)
          (insert-text-button (format "b%d-%d" i j) 'action #'ignore)
          (insert " "))
        (insert "\n")))
    (jetpacs-buffer-forget-exposed)
    (let* ((jetpacs-buffer-budget (cons 5 nil))
           (nodes (with-current-buffer name
                    (jetpacs-buffer--render-region
                     (point-min) (point-max) name))))
      (should (equal (jetpacs-buffer-test--shipped-taps nodes)
                     (jetpacs-buffer-test--authorized-taps name))))))

(ert-deftest jetpacs-buffer-exposure-scope-is-the-document ()
  "SPEC 23.1: authority is scoped to one SurfaceSpec.  `chrome' renders N
screens into one `multi_view'; a later screen must not forget an earlier
screen's records while that screen is still live under the back arrow."
  (let ((name "*e4-doc*") top-pos deep-pos)
    (jetpacs-buffer-test--fill name 20)
    ;; The drill shape: two screens of ONE document showing DIFFERENT
    ;; regions of the SAME buffer.  Two different buffers would not
    ;; reproduce it — `forget-exposed' is per-buffer, so they never
    ;; collide, and the test would pass with the scoping removed.
    ;; Exposures are recorded at RUN starts, which for these lines is the
    ;; line beginning — not an arbitrary offset inside the button.
    (with-current-buffer name
      (save-excursion
        (goto-char (point-min))
        (setq top-pos (line-beginning-position))
        (forward-line 14)
        (setq deep-pos (line-beginning-position))))
    (jetpacs-buffer-forget-exposed)
    (jetpacs-buffer-with-budget
      (with-current-buffer name
        (save-excursion
          ;; Screen 1: the top of the buffer.
          (goto-char (point-min))
          (jetpacs-buffer--render-region
           (point-min) (line-end-position 5) name)
          ;; Screen 2: a drill to a lower region, still one document.
          (goto-char (point-min))
          (forward-line 14)
          (jetpacs-buffer--render-region
           (line-beginning-position) (point-max) name))))
    ;; The drill's own affordance works...
    (should (jetpacs-buffer-exposed-p name deep-pos))
    ;; ...and screen 1's, still visible under the back arrow, survived it.
    (should (jetpacs-buffer-exposed-p name top-pos))
    ;; A NEW document still supersedes: records do not accumulate forever.
    (jetpacs-buffer-with-budget
      (with-current-buffer name
        (save-excursion
          (goto-char (point-min))
          (forward-line 14)
          (jetpacs-buffer--render-region
           (line-beginning-position) (point-max) name))))
    (should (jetpacs-buffer-exposed-p name deep-pos))
    (should-not (jetpacs-buffer-exposed-p name top-pos))))

(ert-deftest jetpacs-buffer-toast-text-is-bounded ()
  "SPEC 18.2 P3 rider: `jetpacs-toast' caps TEXT — the one uncapped text
path.  The ellipsis replaces the tail, so the result never exceeds the
bound."
  (should (= 300 (length (jetpacs-truncate-text (make-string 5000 ?x) 300))))
  (should (string-suffix-p "…" (jetpacs-truncate-text (make-string 5000 ?x) 300)))
  (should (equal "hi" (jetpacs-truncate-text "hi" 300)))
  ;; A zero bound disables the cap rather than truncating to nothing.
  (should (= 5000 (length (jetpacs-truncate-text (make-string 5000 ?x) 0))))
  ;; The cap is WIRED into jetpacs-toast, not merely available.
  (let ((sent nil))
    (cl-letf (((symbol-function 'jetpacs-connected-p) (lambda () t))
              ((symbol-function 'jetpacs-granted-p) (lambda (&rest _) t))
              ((symbol-function 'jetpacs-client) (lambda () 'stub))
              ((symbol-function 'ebp-client-toast)
               (lambda (_c text &rest _) (setq sent text))))
      (jetpacs-toast (make-string 5000 ?x))
      (should (= jetpacs-toast-max-chars (length sent))))))

;;;; Extra aggregate budgets (JA-5a, amendment A2)

(ert-deftest jetpacs-buffer-spend-limit-aggregate ()
  "`jetpacs-buffer-spend-limit' spends one shared per-spec allowance.
A refused spend charges NOTHING, so a smaller later ask still fits."
  (jetpacs-buffer-test--with-client '(:max_table_cells 10)
    (jetpacs-buffer-with-budget
      (should (jetpacs-buffer-spend-limit :max_table_cells 6))
      (should-not (jetpacs-buffer-spend-limit :max_table_cells 5))
      (should (jetpacs-buffer-spend-limit :max_table_cells 4))
      (should-not (jetpacs-buffer-spend-limit :max_table_cells 1))
      ;; Zero/negative asks are free no-ops even at zero remaining.
      (should (jetpacs-buffer-spend-limit :max_table_cells 0)))))

(ert-deftest jetpacs-buffer-spend-limit-joins-nested-budget ()
  "An inner `jetpacs-buffer-with-budget' joins the outer allowance —
same idempotence rule as spans/bytes, or two screens in one multi_view
would each count their tables from zero and GATE 5 would refuse the
whole push."
  (jetpacs-buffer-test--with-client '(:max_table_cells 4)
    (jetpacs-buffer-with-budget
      (should (jetpacs-buffer-spend-limit :max_table_cells 3))
      (jetpacs-buffer-with-budget
        (should-not (jetpacs-buffer-spend-limit :max_table_cells 2))))))

(ert-deftest jetpacs-buffer-spend-limit-unlimited-when-absent ()
  "No client, or a welcome without the key, leaves the spend free —
the push-time GATE 5 aggregate remains the authority."
  (jetpacs-buffer-with-budget
    (should (jetpacs-buffer-spend-limit :max_table_cells 10000)))
  (jetpacs-buffer-test--with-client '(:max_rich_spans 10)
    (jetpacs-buffer-with-budget
      (should (jetpacs-buffer-spend-limit :max_table_cells 10000)))))

(provide 'jetpacs-buffer-test)
;;; jetpacs-buffer-test.el ends here
