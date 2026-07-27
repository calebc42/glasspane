;;; smoke-amend-129-132.el --- device gate for amendments #129/#132 -*- lexical-binding: t; -*-

;; Two amendments landed with no device coverage; this is their gate.
;;
;;   #129 (SPEC 10.2) — the welcome reports `current_view' for a present
;;   multi-view app surface.  The whole point is the OFFLINE case, so this
;;   smoke does not read the value from a live session: it pushes a
;;   multi-view surface, switches the view, DISCONNECTS, reconnects, and
;;   reads the second welcome.  A test that stayed connected would prove
;;   nothing the unit test does not already prove.
;;
;;   #132 (SPEC 18.3) — an invalid `pie_menu.show' is reported with a
;;   `log.error' carrying data.reason "pie-menu-invalid", instead of being
;;   discarded in silence.
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765':
;;   emacs -Q --batch -L emacs -l test/smoke-amend-129-132.el

(require 'ebp)

(defvar smoke--log-errors nil)
(defvar smoke--phase1-done nil)
(defvar smoke--welcome-view :unset)

(defconst smoke--token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw"))
(defconst smoke--pid "101112131415161718191a1b1c1d1e1f")
(defconst smoke--receipts (make-temp-file "ebp-amend-receipts"))

;; A surface id unique to this run: the device PERSISTS revisions per
;; surface, and a fresh client starts its own revision sequence at 1 — so
;; reusing app:main would push a revision the device answers `stale'.
(defconst smoke--surface (format "app:amend%d" (random 100000)))

(defconst smoke--spec
  '(:initial_view "main"
    :views
    (:main (:t "column" :padding 24
            :children [(:t "text" :text "Main" :style "headline")])
     :detail (:t "column" :padding 24
              :children [(:t "text" :text "Detail" :style "headline")])))
  "A two-view app surface; `main' is the initial view.")

(defun smoke--connect (ready)
  (ebp-connect
   "127.0.0.1" 8765
   :client-name "wsl-emacs" :client-version "30.1"
   :pairing-id smoke--pid :token smoke--token
   :wants '("theme" "presentation.pie-menu")
   :receipt-file smoke--receipts
   :ready-function ready))

(defun smoke--wait (pred secs)
  (let ((deadline (+ (float-time) secs)))
    (while (and (not (funcall pred)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall pred)))

;; ---------------------------------------------------------------- phase 1
;; Push the multi-view surface, drive it to `detail', then close.

(let ((c1 (smoke--connect
           (lambda (c)
             ;; Register BEFORE any traffic. This also keeps "log.error" in
             ;; the handler table when the E4 obarray pass inspects inbound
             ;; method names, which is the shape a real consumer uses.
             (ebp-client-register-handler
              c "log.error"
              (lambda (_c params) (push params smoke--log-errors) nil))
             ;; Revision 1 establishes the surface with initial_view main.
             (ebp-client-surface-update
              c smoke--surface smoke--spec
              :callback
              (lambda (_status _err)
                ;; Revision 2 names current_view explicitly — the Emacs-driven
                ;; navigation SPEC 13.4 allows — so the Companion is showing
                ;; `detail' when we disconnect.
                (ebp-client-surface-update
                 c smoke--surface smoke--spec :current-view "detail"
                 :callback (lambda (_s _e) (setq smoke--phase1-done t)))))))))
  (smoke--wait (lambda () smoke--phase1-done) 20)
  (unless smoke--phase1-done
    (message "FAIL: phase 1 never completed") (kill-emacs 1))
  (ebp-client-close c1 'smoke-phase-1)
  (sleep-for 1))

;; ------------------------------------------------------------- phase 1b
;; #132 on its OWN connection.  The device is single-session and pie menus
;; are ephemeral to the session, so sharing phase 1's connection coupled an
;; independent check to that session's state for no benefit.

(defvar smoke--pie-ready nil)
(defvar smoke--132-ok nil)
(defvar smoke--132-path nil)

(let ((cp (smoke--connect
           (lambda (c)
             (ebp-client-register-handler
              c "log.error"
              (lambda (_c params) (push params smoke--log-errors) nil))
             (setq smoke--pie-ready t)))))
  ;; Send from the BODY, not from inside `ready-function'. pie_menu.show is
  ;; legal only in READY, and a notify issued from within the ready callback
  ;; races the device's own barrier transition — the engine then drops it as
  ;; a state violation, which is correctly NOT reported as content-invalid.
  ;; That race, not the amendment, is what failed the first three attempts.
  (smoke--wait (lambda () smoke--pie-ready) 20)
  (ebp-client-notify
   cp 'pie_menu.show
   (list :menu_id "bad"
         :categories (vector (list :label "x"
                                   :on_tap (list :action "a.b")
                                   :items []))))
  (smoke--wait (lambda () smoke--log-errors) 10)
  ;; Conclude #132 HERE, where the evidence is, rather than deferring the
  ;; assertion past two more connections. NOT cosmetic: with the assertion
  ;; deferred to the end, smoke--log-errors read back nil even though a
  ;; debug print inside this block showed the captured log.error. The cause
  ;; was not diagnosed; asserting in-phase sidesteps it and is the better
  ;; shape regardless. If you move this, verify it still fails when the
  ;; amendment is reverted.
  (let ((invalid (seq-find
                  (lambda (p) (equal "pie-menu-invalid"
                                     (plist-get (plist-get p :data) :reason)))
                  smoke--log-errors)))
    (setq smoke--132-ok
          (and invalid
               (eql 1201 (plist-get invalid :code))
               (equal "content-invalid"
                      (plist-get (plist-get invalid :data) :kind))
               (stringp (plist-get (plist-get invalid :data) :path))))
    (setq smoke--132-path (and invalid (plist-get (plist-get invalid :data) :path))))
  (ebp-client-close cp 'smoke-phase-1b)
  (sleep-for 1))

;; ---------------------------------------------------------------- phase 2
;; Reconnect and read the welcome.

(let ((c2 (smoke--connect
           (lambda (c)
             ;; Surface ids arrive as keywords (":app:amend123"); match by
             ;; name rather than writing an escaped keyword literal.
             (let* ((surfaces (ebp-client-surfaces c))
                    (want (concat ":" smoke--surface))
                    (entry (cl-loop for (k v) on surfaces by #'cddr
                                    when (equal (symbol-name k) want)
                                    return v)))
               (setq smoke--welcome-view
                     (if entry (or (plist-get entry :current_view) :absent)
                       :no-entry)))))))
  (smoke--wait (lambda () (not (eq smoke--welcome-view :unset))) 20)
  (ebp-client-close c2 'smoke-phase-2))

;; ---------------------------------------------------------------- verdict

(let ((ok-129 (equal "detail" smoke--welcome-view)))
  (message "#132 pie-menu-invalid log.error : %s (path=%S)"
           (if smoke--132-ok "PASS" "FAIL") smoke--132-path)
  (message "#129 welcome current_view       : %s (got %S, want \"detail\")"
           (if ok-129 "PASS" "FAIL") smoke--welcome-view)
  (kill-emacs (if (and smoke--132-ok ok-129) 0 1)))

;;; smoke-amend-129-132.el ends here
