;;; jetpacs-emacs-ui-test.el --- JA-3c/3d exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JA-3 exit-gate halves in jetpacs-emacs-ui and jetpacs-echo
;; (docs/PLAN-jetpacs-apps.md JA-3): imenu flatten over BOTH index
;; shapes; the SPEC 23.1 exposure gates on the buffer-addressed
;; actions; the jetpacs-dialog--static-candidates obarray guard (the
;; rung's named prerequisite); and the message→toast bridge's gates —
;; default-off, flow-gated, own-chatter-filtered, re-entrancy-safe.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'jetpacs-emacs-ui)
(require 'jetpacs-echo)
(require 'jetpacs-dialog)

;;;; imenu flatten (the plan's two index shapes)

(ert-deftest jetpacs-emacs-ui-imenu-flatten-both-shapes ()
  (with-temp-buffer
    (insert (make-string 100 ?x))
    (let* ((marker (copy-marker 30))
           (index `(("Top" . 5)
                    ("Funcs" ("f" . 10) ("g" 20 ignore))
                    ("Marked" . ,marker)
                    ("*Rescan*" . -99)
                    ("BadPos" . 0)))
           (flat (jetpacs-emacs-ui-imenu-flatten index)))
      ;; (NAME . POS) leaf.
      (should (equal (assoc "Top" flat) '("Top" . 5)))
      ;; Nested submenu breadcrumbs, both leaf shapes.
      (should (equal (assoc "Funcs / f" flat) '("Funcs / f" . 10)))
      (should (equal (assoc "Funcs / g" flat) '("Funcs / g" . 20)))
      ;; Markers dereference to integers.
      (should (equal (assoc "Marked" flat) '("Marked" . 30)))
      ;; *Rescan* and sub-1 positions are dropped.
      (should-not (assoc "*Rescan*" flat))
      (should-not (assoc "BadPos" flat)))))

(ert-deftest jetpacs-emacs-ui-imenu-flatten-drops-dead-markers ()
  (let ((marker (with-temp-buffer (copy-marker 1))))
    ;; The temp buffer died with the marker pointing into it.
    (should-not (jetpacs-emacs-ui-imenu-flatten
                 `(("Dead" . ,marker))))))

;;;; SPEC 23.1 exposure gates on the actions

(defun jetpacs-emacs-ui-test--action (name)
  (gethash name jetpacs-action-handlers))

(ert-deftest jetpacs-emacs-ui-view-requires-exposure ()
  "A view of a buffer the hub never offered is REJECTED; a listed one
is accepted; a dead one is stale (re-presentable)."
  (let ((act (jetpacs-emacs-ui-test--action "jetpacs.emacs.view")))
    (should act)
    (jetpacs-buffer-forget-exposed)
    (with-current-buffer (get-buffer-create "*ja3-listed*")
      (fundamental-mode))
    (unwind-protect
        (progn
          ;; Never offered -> rejected, even though the buffer exists.
          (should (eq (funcall act '(:buffer "*ja3-listed*") nil)
                      'rejected))
          ;; The hub's row build is what authorizes.
          (jetpacs-buffer-expose-buffer "*ja3-listed*" "jetpacs.emacs.view")
          (should (eq (funcall act '(:buffer "*ja3-listed*") nil)
                      'accepted))
          ;; A dead buffer is stale.
          (should (eq (funcall act '(:buffer "*ja3-gone*") nil) 'stale)))
      (jetpacs-buffer-forget-exposed))))

(ert-deftest jetpacs-emacs-ui-hub-rows-expose-what-they-offer ()
  "Building the hub records one view exposure per listed buffer —
authorized == offered, the E4 invariant applied to whole buffers."
  (jetpacs-buffer-forget-exposed)
  (with-current-buffer (get-buffer-create "*ja3-hub-buf*")
    (fundamental-mode))
  (unwind-protect
      (progn
        (jetpacs-emacs-ui--hub-rows)
        (should (jetpacs-buffer-exposed-buffer-p
                 "*ja3-hub-buf*" "jetpacs.emacs.view"))
        ;; And NOT for verbs the hub does not offer.
        (should-not (jetpacs-buffer-exposed-buffer-p
                     "*ja3-hub-buf*" "jetpacs.emacs.palette")))
    (jetpacs-buffer-forget-exposed)))

(ert-deftest jetpacs-emacs-ui-drilled-screen-exposes-its-verbs ()
  "The drilled screen authorizes imenu and palette for ITS buffer."
  (jetpacs-buffer-forget-exposed)
  (with-current-buffer (get-buffer-create "*ja3-drilled*")
    (fundamental-mode)
    (erase-buffer)
    (insert "hello\n"))
  (unwind-protect
      (progn
        (jetpacs-emacs-ui--buffer-screen "*ja3-drilled*" nil)
        (should (jetpacs-buffer-exposed-buffer-p
                 "*ja3-drilled*" "jetpacs.emacs.imenu"))
        (should (jetpacs-buffer-exposed-buffer-p
                 "*ja3-drilled*" "jetpacs.emacs.palette")))
    (jetpacs-buffer-forget-exposed)))

;;;; Palette execution (offline, headless — the shape the device is)

(ert-deftest jetpacs-emacs-ui-palette-executes-a-key-binding-headless ()
  "The chosen key's COMMAND runs in the target buffer even though that
buffer is in NO WINDOW — the device reality.  `execute-kbd-macro' fails
exactly this test: its command loop runs against the selected window's
buffer, so the key self-inserts into *scratch* instead (the poc's bug,
caught on hardware and pinned here)."
  (defun jetpacs-emacs-ui-test--tapped ()
    (interactive)
    (goto-char (point-max))
    (insert "TAPPED\n"))
  (with-current-buffer (get-buffer-create "*ja3-palette*")
    (fundamental-mode)
    (erase-buffer)
    (insert "hello\n")
    (let ((map (make-sparse-keymap)))
      (define-key map (kbd "T") #'jetpacs-emacs-ui-test--tapped)
      (use-local-map map)))
  (cl-letf (((symbol-function 'completing-read)
             (lambda (&rest _) "T  ·  emacs-ui-test--tapped"))
            ((symbol-function 'jetpacs-buffer-defer-refresh) #'ignore))
    ;; The display string must be the one the candidates really mint.
    (let* ((cands (jetpacs-keymap-palette-candidates
                   (get-buffer "*ja3-palette*")))
           ;; target is (key COMMAND . KEY-DESC) since the shadowing fix.
           (row (seq-find (lambda (c) (equal (cdr (cddr c)) "T")) cands)))
      (should row)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) (car row))))
        (jetpacs-emacs-ui--palette-flow "*ja3-palette*"))))
  (with-current-buffer "*ja3-palette*"
    (should (string-search "TAPPED" (buffer-string)))
    ;; And it did NOT leak into the selected window's buffer.
    (should-not (with-current-buffer (window-buffer (selected-window))
                  (string-search "TAPPED" (buffer-string))))))

;;;; The static-candidates obarray guard (the rung's prerequisite)

(ert-deftest jetpacs-emacs-ui-static-candidates-obarray-guard ()
  "An obarray collection is treated as dynamic: no enumeration, no
sort, nil return — the M-x picker path.  A list still enumerates."
  (should-not (jetpacs-dialog--static-candidates obarray nil))
  (should (equal (jetpacs-dialog--static-candidates '("b" "a") nil)
                 '("a" "b"))))

;;;; The message→toast bridge (JA-3d)

(defmacro jetpacs-emacs-ui-test--with-echo (flow-p &rest body)
  "Run BODY with the bridge installed, toasts captured into `sent',
device-flow stubbed to FLOW-P, and everything restored after."
  (declare (indent 1))
  `(let ((sent '()))
     (cl-letf (((symbol-function 'jetpacs-device-flow-p)
                (lambda () ,flow-p))
               ((symbol-function 'jetpacs-connected-p) (lambda () t))
               ((symbol-function 'jetpacs-toast)
                (cl-function (lambda (text &key duration-s)
                               (ignore duration-s)
                               (push text sent) t))))
       (unwind-protect
           (progn (jetpacs-echo-install)
                  (let ((jetpacs-echo-throttle-seconds 0)
                        (jetpacs-echo--last 0.0))
                    ,@body))
         (jetpacs-echo-uninstall)))))

(ert-deftest jetpacs-echo-defaults-off-and-uninstalled ()
  "Loading the module must not touch `message'."
  (should-not (advice-member-p #'jetpacs-echo--after-message 'message))
  (should-not (default-value 'jetpacs-echo-toast)))

(ert-deftest jetpacs-echo-mirrors-flow-messages ()
  (jetpacs-emacs-ui-test--with-echo t
    (message "hello %d" 7)
    (should (equal sent '("hello 7")))))

(ert-deftest jetpacs-echo-silent-outside-a-flow ()
  (jetpacs-emacs-ui-test--with-echo nil
    (message "ambient desktop noise")
    (should (null sent))))

(ert-deftest jetpacs-echo-filters-own-chatter ()
  "Bridge chatter must not echo back to the device — at best noise, at
worst a loop."
  (jetpacs-emacs-ui-test--with-echo t
    (message "jetpacs-emacs-ui: something happened")
    (message "ebp: overloaded")
    (should (null sent))))

(ert-deftest jetpacs-echo-throttle-keeps-the-latest ()
  (jetpacs-emacs-ui-test--with-echo t
    (let ((jetpacs-echo-throttle-seconds 60))
      (message "first")                 ; sent immediately (last = 0)
      (message "second")                ; pending
      (message "third")                 ; replaces second
      (should (equal sent '("first")))
      (should (equal jetpacs-echo--pending "third"))
      (jetpacs-echo--flush)
      (should (equal sent '("third" "first")))
      (should-not jetpacs-echo--pending))))

(ert-deftest jetpacs-echo-reentrancy-guard-holds ()
  "A toast whose send itself logs a message must not recurse."
  (let ((sent 0))
    (cl-letf (((symbol-function 'jetpacs-device-flow-p) (lambda () t))
              ((symbol-function 'jetpacs-connected-p) (lambda () t))
              ((symbol-function 'jetpacs-toast)
               (cl-function (lambda (_text &key duration-s)
                              (ignore duration-s)
                              (cl-incf sent)
                              ;; The hazardous shape: the sender logs.
                              (message "toast dispatched")
                              t))))
      (unwind-protect
          (progn (jetpacs-echo-install)
                 (let ((jetpacs-echo-throttle-seconds 0)
                       (jetpacs-echo--last 0.0))
                   (message "user-visible result")
                   ;; One toast for the user message; the sender's own
                   ;; log did NOT re-enter ("toast dispatched" would
                   ;; otherwise recurse forever).
                   (should (= sent 1))))
        (jetpacs-echo-uninstall)))))

(ert-deftest jetpacs-emacs-ui-mx-is-a-global-verb ()
  "`jetpacs-emacs-ui-mx-button' renders in other owners' top bars
(the CHROME-VOCABULARY top-bar contract), so the verb must carry the
:any-surface exemption and the button must name it."
  (should (gethash "jetpacs.emacs.mx" jetpacs--any-surface-actions))
  (let ((btn (jetpacs-emacs-ui-mx-button)))
    (should (equal (plist-get btn :icon) "terminal"))
    (should (equal (plist-get (plist-get btn :on_tap) :action)
                   "jetpacs.emacs.mx"))))

;;;; edit.command (R6, PLAN-glasspane-completion.md)

(require 'ebp-sync)

(defmacro jetpacs-emacs-ui-test--with-edit-command (content &rest body)
  "Attached buffer holding CONTENT as doc:r6.txt/body, client attached.
Binds `client', `buf', `sent' (captured requests, newest first) and
`notices' (captured snackbar texts).  Drains pending flow timers while
the stubs are still up, so no run leaks into a later test."
  (declare (indent 1))
  `(let* ((client (ebp-client-create :receipt-file (make-temp-file "r6")))
          (buf (generate-new-buffer " *r6*"))
          (sent nil) (notices nil))
     (ignore sent notices)
     (unwind-protect
         (progn
           (jetpacs-attach client)
           (with-current-buffer buf
             (insert ,content)
             (puthash (cons "doc:r6.txt" "body")
                      (list :session "S" :seq 0 :text ,content :cursor 0)
                      (ebp-client-editors client))
             (ebp-sync-attach client "doc:r6.txt" "body" buf))
           (cl-letf (((symbol-function 'ebp-client--request)
                      (lambda (_c method params cb &optional _t)
                        (push (list method params cb) sent)))
                     ((symbol-function 'jetpacs-shell-notify)
                      (lambda (text &rest _) (push text notices))))
             ,@body
             (cl-loop repeat 10 do (accept-process-output nil 0.02))))
       (with-current-buffer buf (ebp-sync-detach))
       (kill-buffer buf)
       (jetpacs-detach) (jetpacs-test-reset-state))))

(defun jetpacs-emacs-ui-test--edit-command (args)
  (funcall (gethash "edit.command" jetpacs-action-handlers)
           args '(:surface "app:demo")))

(ert-deftest jetpacs-emacs-ui-edit-command-gates ()
  "Shape violations reject, a moved seq is stale, fresh accepts — and
nothing runs inside the dispatch (D2)."
  (jetpacs-emacs-ui-test--with-edit-command "hello world"
    (should (eq (jetpacs-emacs-ui-test--edit-command
                 '(:document "doc:r6.txt" :editor_id "body"
                   :session "S" :seq "NaN" :cursor 0))
                'rejected))
    (should (eq (jetpacs-emacs-ui-test--edit-command
                 '(:document "doc:r6.txt" :editor_id "body"
                   :session "S" :seq 7 :cursor 0 :command "ignore"))
                'stale))
    (should (eq (jetpacs-emacs-ui-test--edit-command
                 '(:document "doc:r6.txt" :editor_id "body"
                   :session "S" :seq 0 :cursor 0 :command "ignore"))
                'accepted))
    (should (equal (with-current-buffer buf (buffer-string))
                   "hello world"))))

(ert-deftest jetpacs-emacs-ui-edit-command-runs-at-device-region ()
  "The command runs at the DEVICE's point and region — `upcase-region'
over the device's selection upcases exactly that span — and the text
change flushes back as ordinary `edit.apply' traffic."
  (jetpacs-emacs-ui-test--with-edit-command "hello world"
    (should (eq (jetpacs-emacs-ui-test--edit-command
                 '(:document "doc:r6.txt" :editor_id "body"
                   :session "S" :seq 0 :cursor 5 :sel_start 0 :sel_end 5
                   :command "upcase-region"))
                'accepted))
    (cl-loop repeat 30
             until (with-current-buffer buf
                     (equal (buffer-string) "HELLO world"))
             do (accept-process-output nil 0.02))
    (should (equal (with-current-buffer buf (buffer-string))
                   "HELLO world"))
    (let ((apply-frame (cl-find 'edit.apply sent :key #'car)))
      (should apply-frame)
      (should (equal (plist-get (nth 1 apply-frame) :text) "HELLO"))
      (should (= (plist-get (nth 1 apply-frame) :start) 0))
      (should (= (plist-get (nth 1 apply-frame) :del) 5)))))

(ert-deftest jetpacs-emacs-ui-edit-command-refuses-noncommands ()
  "The nested SPEC 17.7 allowlist: an eval-shaped name is interned
softly, gated, and refused with a snackbar — it never reaches any
dispatcher — and `jetpacs-emacs-ui-command-predicate' refuses real
commands too when told to."
  (jetpacs-emacs-ui-test--with-edit-command "abc"
    (jetpacs-emacs-ui-test--edit-command
     '(:document "doc:r6.txt" :editor_id "body" :session "S" :seq 0
       :cursor 0 :command "(shell-command \"boom\")"))
    (cl-loop repeat 30 until notices do (accept-process-output nil 0.02))
    (should (string-match-p "Not a command" (car notices)))
    ;; The default IS the M-x surface's own gate, not bare commandp: a
    ;; suppressed command (suspends the host) is refused though
    ;; commandp accepts it.  Reverting the default to commandp fails
    ;; here (R6 review).
    (setq notices nil)
    (should (commandp 'suspend-frame))
    (jetpacs-emacs-ui-test--edit-command
     '(:document "doc:r6.txt" :editor_id "body" :session "S" :seq 0
       :cursor 0 :command "suspend-frame"))
    (cl-loop repeat 30 until notices do (accept-process-output nil 0.02))
    (should (string-match-p "Not a command" (car notices)))
    (setq notices nil)
    (let ((jetpacs-emacs-ui-command-predicate #'ignore))
      (jetpacs-emacs-ui-test--edit-command
       '(:document "doc:r6.txt" :editor_id "body" :session "S" :seq 0
         :cursor 0 :command "upcase-region"))
      (cl-loop repeat 30 until notices do (accept-process-output nil 0.02))
      (should (string-match-p "Not a command" (car notices))))
    (should (equal (with-current-buffer buf (buffer-string)) "abc"))
    (should-not (cl-find 'edit.apply sent :key #'car))))

(ert-deftest jetpacs-emacs-ui-edit-command-move-only-frame ()
  "A command that only moves point reports the SPEC 19.4 move-only
form: no start/del/text/len, the UNCHANGED seq, the new cursor."
  (jetpacs-emacs-ui-test--with-edit-command "hello"
    (jetpacs-emacs-ui-test--edit-command
     '(:document "doc:r6.txt" :editor_id "body" :session "S" :seq 0
       :cursor 1 :command "forward-char"))
    (cl-loop repeat 30 until sent do (accept-process-output nil 0.02))
    (let ((frame (cl-find 'edit.apply sent :key #'car)))
      (should frame)
      (let ((p (nth 1 frame)))
        (should-not (plist-member p :start))
        (should-not (plist-member p :text))
        (should (= (plist-get p :seq) 0))
        (should (= (plist-get p :cursor) 2))))))

(ert-deftest jetpacs-emacs-ui-edit-command-stale-flow-drops ()
  "A seq that moves between dispatch and flow drops the run QUIETLY —
the coordinates describe a document state already left, the raced
caret's rule."
  (jetpacs-emacs-ui-test--with-edit-command "abc"
    (should (eq (jetpacs-emacs-ui-test--edit-command
                 '(:document "doc:r6.txt" :editor_id "body" :session "S"
                   :seq 0 :cursor 0 :sel_start 0 :sel_end 3
                   :command "upcase-region"))
                'accepted))
    (setf (plist-get (gethash (cons "doc:r6.txt" "body")
                              (ebp-client-editors client))
                     :seq)
          1)
    (cl-loop repeat 10 do (accept-process-output nil 0.02))
    (should (equal (with-current-buffer buf (buffer-string)) "abc"))
    (should-not sent)))

(ert-deftest jetpacs-emacs-ui-edit-command-mx-bridge ()
  "An op with no command bridges M-x, scoped by
`jetpacs-command-visible-p' — the palette's posture."
  (jetpacs-emacs-ui-test--with-edit-command "hello"
    (let (predicate-seen)
      (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p)
                 (lambda () t))
                ((symbol-function 'completing-read)
                 (lambda (_prompt _coll &optional pred &rest _)
                   (setq predicate-seen pred)
                   "forward-char")))
        (jetpacs-emacs-ui-test--edit-command
         '(:document "doc:r6.txt" :editor_id "body" :session "S" :seq 0
           :cursor 0))
        (cl-loop repeat 30 until sent do (accept-process-output nil 0.02))
        (should (eq predicate-seen #'jetpacs-command-visible-p))
        (should (cl-find 'edit.apply sent :key #'car))))))

(provide 'jetpacs-emacs-ui-test)
;;; jetpacs-emacs-ui-test.el ends here

;;;; Adversarial-review remediation (2026-07-27)

(ert-deftest jetpacs-emacs-ui-prompting-flows-refuse-without-a-bridge ()
  "A flow whose whole purpose is to ASK must not raise a prompt it
cannot route: with no bridge the advice falls through to the REAL
minibuffer, and on a daemon that is a wedge nobody can answer while the
device has already been told `accepted'."
  (let ((notified nil) (prompted nil))
    (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p) (lambda () nil))
              ((symbol-function 'jetpacs-shell-notify)
               (lambda (text &rest _) (setq notified text)))
              ((symbol-function 'completing-read)
               (lambda (&rest _) (setq prompted t) "")))
      (jetpacs-emacs-ui--with-prompting #'jetpacs-emacs-ui--mx-flow)
      (should-not prompted)
      (should notified))))

(ert-deftest jetpacs-emacs-ui-prompting-flow-errors-are-reported-not-lost ()
  "A flow error must reach the user and carry the SYMBOL only (23.3),
never die unreported in a timer."
  (let ((notified nil) (logged '()))
    (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p) (lambda () t))
              ((symbol-function 'jetpacs-shell-notify)
               (lambda (text &rest _) (setq notified text)))
              ((symbol-function 'message)
               (lambda (fmt &rest args) (push (apply #'format fmt args) logged))))
      (jetpacs-emacs-ui--with-prompting
       (lambda () (error "SECRET-DOCUMENT-TEXT")))
      (should notified)
      (should-not (cl-some (lambda (l) (string-match-p "SECRET" l)) logged)))))

(ert-deftest jetpacs-emacs-ui-hub-exposure-tracks-what-is-offered ()
  "Authorized == offered: a buffer that stops being listed loses its
grant, and a killed buffer's grant dies with it (names get reused)."
  (jetpacs-buffer-forget-exposed)
  (let ((gone (get-buffer-create "*ja3-transient*")))
    (with-current-buffer gone (fundamental-mode))
    (jetpacs-emacs-ui--hub-rows)
    (should (jetpacs-buffer-exposed-buffer-p
             "*ja3-transient*" "jetpacs.emacs.view"))
    ;; Killing it revokes the grant, so a later buffer of the same name
    ;; cannot inherit authority nothing on screen ever granted it.
    (kill-buffer gone)
    (should-not (jetpacs-buffer-exposed-buffer-p
                 "*ja3-transient*" "jetpacs.emacs.view")))
  (jetpacs-buffer-forget-exposed))

(ert-deftest jetpacs-emacs-ui-hub-charges-the-shared-byte-budget ()
  "Hub rows are charged against the SPEC 4.5 byte budget and truncate
with a caption — rows built outside the Tier-0 walk were invisible to
that accounting, so a drilled screen below believed it owned the whole
frame and the finished document blew max_frame_bytes (which refuses the
WHOLE spec, rendering nothing at all).

Drives `--hub-screen', not `--charge-rows': asserting the helper alone
passes with the helper UNWIRED, which is the whole failure mode."
  (dotimes (i 30)
    (with-current-buffer (get-buffer-create (format "*ja3-bulk-%d*" i))
      (fundamental-mode)))
  (unwind-protect
      (let* ((jetpacs-buffer-budget (cons nil 400))
             (screen (jetpacs-emacs-ui--hub-screen nil))
             (json (jetpacs-node->canonical-json screen)))
        ;; The budget was spent down rather than left untouched...
        (should (< (cdr jetpacs-buffer-budget) 400))
        ;; ...the screen says it truncated...
        (should (string-search "surface budget" json))
        ;; ...and the result fits the budget it was given, which is the
        ;; property that keeps the whole document pushable.
        (should (< (string-bytes json) 4000))
        ;; Not vacuous: unbudgeted, the same hub is much bigger.
        (let* ((jetpacs-buffer-budget nil)
               (full (jetpacs-node->canonical-json
                      (jetpacs-emacs-ui--hub-screen nil))))
          (should (> (string-bytes full) (string-bytes json)))))
    (dotimes (i 30) (kill-buffer (format "*ja3-bulk-%d*" i)))
    (jetpacs-buffer-forget-exposed)))

(ert-deftest jetpacs-emacs-ui-live-watch-gives-up-on-repeated-failure ()
  "The tick re-read absorbs only what a push logs SYNCHRONOUSLY;
surface.update concludes asynchronously, so a failure logged from its
callback lands after the snapshot — a 1 Hz self-sustaining loop when
*Messages* is the watched buffer.  A consecutive-failure bound is the
guard that does not depend on seeing the future."
  (with-current-buffer (get-buffer-create "*ja3-watch*") (fundamental-mode))
  (unwind-protect
      (cl-letf (((symbol-function 'jetpacs-connected-p) (lambda () t))
                ((symbol-function 'jetpacs-emacs-ui--top-buffer)
                 (lambda () "*ja3-watch*"))
                ((symbol-function 'jetpacs-shell-push)
                 (lambda (&rest _) (error "push refused"))))
        (setq jetpacs-emacs-ui--live-buffer "*ja3-watch*"
              jetpacs-emacs-ui--live-tick 0
              jetpacs-emacs-ui--live-failures 0
              jetpacs-emacs-ui--live-timer 'fake)
        (let ((inhibit-message t))
          (dotimes (_ jetpacs-emacs-ui-live-max-failures)
            (with-current-buffer "*ja3-watch*" (insert "x"))
            (jetpacs-emacs-ui--live-poll)))
        ;; Gave up rather than retrying forever.
        (should (null jetpacs-emacs-ui--live-timer))
        (should (null jetpacs-emacs-ui--live-buffer)))
    (jetpacs-emacs-ui--live-stop)))

(ert-deftest jetpacs-emacs-ui-visit-region-drills-to-the-destination ()
  "`results.visit' must land somewhere: the default seam only armed the
region and re-pushed the CURRENT surface, so the slice showed solely if
a screen for the destination already happened to be on the stack."
  (should (eq jetpacs-results-visit-region-function
              #'jetpacs-emacs-ui-visit-region))
  (with-current-buffer (get-buffer-create "*ja3-dest*")
    (fundamental-mode) (erase-buffer) (insert "one\ntwo\nthree\n"))
  (jetpacs-buffer-forget-exposed)
  (let ((pushed nil))
    (cl-letf (((symbol-function 'jetpacs-emacs-ui--push-buffer-screen)
               (lambda (name) (setq pushed name)))
              ((symbol-function 'jetpacs-emacs-ui--top-buffer) (lambda () nil)))
      (jetpacs-emacs-ui-visit-region "*ja3-dest*" 1 5 "hit" 1)
      ;; The region is armed for the destination...
      (should (equal (jetpacs-results-region-buffer) "*ja3-dest*"))
      ;; ...the destination is authorized for the view verb...
      (should (jetpacs-buffer-exposed-buffer-p
               "*ja3-dest*" "jetpacs.emacs.view"))
      ;; ...and the drill is DEFERRED (the seam runs inside dispatch).
      (should-not pushed)
      (dotimes (_ 3) (accept-process-output nil 0.01))
      (should (equal pushed "*ja3-dest*"))))
  (jetpacs-results-clear-region)
  (jetpacs-buffer-forget-exposed))
