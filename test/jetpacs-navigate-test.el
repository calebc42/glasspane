;;; jetpacs-navigate-test.el --- JA-2c buffer-view host exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JA-2c navigator half (docs/PLAN-jetpacs-apps.md, B4).  The drill
;; seam is stubbed with a recorder — the chrome suite tests the real
;; implementation — and the D2 gate drives the REAL `jetpacs--dispatch'.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-tablist)
(require 'jetpacs-navigate)

(defmacro jetpacs-navigate-test--with-drill (recorder &rest body)
  "Bind the drill seam to a RECORDER list collector returning t."
  (declare (indent 1))
  `(let ((,recorder nil))
     (let ((jetpacs-navigate-drill-function
            (lambda (surface builder label)
              (push (list surface builder label) ,recorder)
              t)))
       (unwind-protect (progn ,@body)
         (jetpacs-test-reset-state)))))

(ert-deftest jetpacs-navigate-buffer-calls-drill-seam ()
  (with-current-buffer (get-buffer-create "*nav-host*")
    (erase-buffer)
    ;; A TAPPABLE region: exposure records are written only where a tap
    ;; descriptor is actually emitted.
    (insert-text-button "go" 'action #'ignore)
    (insert "\n"))
  (jetpacs-navigate-test--with-drill rec
    (should (equal (jetpacs-navigate-buffer "*nav-host*" "app:demo")
                   "app:demo"))
    (pcase-let ((`(,surface ,builder ,label) (car rec)))
      (should (equal surface "app:demo"))
      (should (equal label "*nav-host*"))
      (should (functionp builder))
      (let ((nodes (funcall builder)))
        (should (consp nodes))
        (jetpacs-check-profile (vconcat nodes) 'app)
        ;; The drill render armed 23.1 exposure for the button's tap.
        (should (jetpacs-buffer-exposed-p "*nav-host*" 1))))))

(ert-deftest jetpacs-navigate-thunk-switch-drills ()
  (with-current-buffer (get-buffer-create "*nav-golden*")
    (erase-buffer)
    (insert "drill me\n"))
  (jetpacs-navigate-test--with-drill rec
    (jetpacs-navigate-thunk (lambda () (switch-to-buffer "*nav-golden*"))
                            "app:demo")
    (should (= (length rec) 1))
    (should (equal (nth 0 (car rec)) "app:demo"))))

(ert-deftest jetpacs-navigate-thunk-defers-in-handler ()
  "The D2 gate: inside a dispatch the thunk defers via flow-continue,
carrying the eagerly-captured D1 surface; the flow marker rides."
  (let ((deferred '()) (ran nil) (flow-in-thunk :unset) (fsurf :unset))
    (jetpacs-navigate-test--with-drill rec
      (cl-letf (((symbol-function 'run-at-time)
                 (lambda (_time _rep fn &rest _) (push fn deferred) nil)))
        (let ((status (jetpacs--dispatch
                       nil '(:action "nav.test" :surface "app:demo")
                       (lambda (_args _params)
                         (jetpacs-navigate-thunk
                          (lambda ()
                            (setq ran t
                                  flow-in-thunk (jetpacs-device-flow-p)
                                  fsurf (jetpacs-flow-surface))
                            (switch-to-buffer
                             (get-buffer-create "*nav-host*"))))
                         'accepted))))
          (should (eq status 'accepted))
          (should-not ran)
          (should (= (length deferred) 1))
          (should (null rec))))
      ;; Fire the continuation outside the extent.
      (funcall (car deferred))
      (should ran)
      (should (eq flow-in-thunk t))
      (should (equal fsurf "app:demo"))
      (should (equal (nth 0 (car rec)) "app:demo")))))

(ert-deftest jetpacs-navigate-thunk-nothing-to-show ()
  (jetpacs-navigate-test--with-drill rec
    (setq jetpacs-shell--snackbar nil)
    (jetpacs-navigate-thunk #'ignore "app:demo")
    (should (null rec))
    (should (equal jetpacs-shell--snackbar "Nothing to show"))))

(ert-deftest jetpacs-navigate-no-drill-host ()
  (get-buffer-create "*nav-host*")
  (let ((jetpacs-navigate-drill-function nil))
    (setq jetpacs-shell--snackbar nil)
    (should-not (jetpacs-navigate-buffer "*nav-host*" "app:demo"))
    (should (equal jetpacs-shell--snackbar "No navigation host")))
  (should-not (jetpacs-navigate-buffer "*no such buffer*")))

(ert-deftest jetpacs-navigate-dead-buffer-screen ()
  (get-buffer-create "*nav-tmp*")
  (let ((builder (jetpacs-navigate--screen-builder "*nav-tmp*")))
    (kill-buffer "*nav-tmp*")
    (let ((nodes (funcall builder)))
      (should (= (length nodes) 1))
      (should (equal (plist-get (car nodes) :t) "text"))
      (should (equal (plist-get (car nodes) :style) "caption"))
      (should (string-match-p "no longer exists"
                              (plist-get (car nodes) :text)))
      (jetpacs-check-profile (vconcat nodes) 'app))))

(ert-deftest jetpacs-navigate-thunk-error-redaction ()
  (jetpacs-navigate-test--with-drill rec
    (let ((logged '()))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (push (apply #'format fmt args) logged))))
        (setq jetpacs-shell--snackbar nil)
        (jetpacs-navigate-thunk (lambda () (error "SECRET-PAYLOAD"))
                                "app:demo"))
      (should-not (cl-some (lambda (s) (string-match-p "SECRET-PAYLOAD" s))
                           logged))
      (should-not (and jetpacs-shell--snackbar
                       (string-match-p "SECRET-PAYLOAD"
                                       jetpacs-shell--snackbar)))
      (should (cl-some (lambda (s) (string-match-p "error" s)) logged)))))

(ert-deftest jetpacs-navigate-tablist-seam-wired ()
  (should (eq jetpacs-tablist-view-buffer-function
              #'jetpacs-navigate-buffer)))


;;;; E2c: refuse rather than guess

(ert-deftest jetpacs-navigate-ownerless-surfaceless-refuses ()
  "An OWNERLESS handler of a SPEC 14.4 surfaceless event has no honest
target: `app:main' would be a guess about which owner's screen to
seize.  The navigator refuses (nil, snackbar) and the handler's own
answer stands — asserted AFTER the dispatch returns, never inside it."
  (let ((drilled nil) (status nil) (notified nil))
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &rest _) (push text notified))))
          (let ((jetpacs-navigate-drill-function
                 (lambda (&rest args) (push args drilled) t)))
            (jetpacs-defaction "bare.show"
                               (lambda (_a _p)
                                 (jetpacs-navigate-buffer "*scratch*")
                                 'accepted))
            (setq status (jetpacs--dispatch
                          nil '(:action "bare.show")
                          (gethash "bare.show" jetpacs-action-handlers)))))
      (jetpacs-undefaction "bare.show")
      (jetpacs-test-reset-state))
    (should (eq status 'accepted))
    (should (null drilled))
    (should (member "No target surface" notified))))

(ert-deftest jetpacs-navigate-owned-handler-resolves-its-own-surface ()
  "With E2a binding the registering owner across the dispatch, an OWNED
handler's surfaceless drill lands on its own surface — the mail
reminder tap that used to drill into another owner's screen."
  (let ((drilled nil) (status nil))
    (unwind-protect
        (let ((jetpacs-navigate-drill-function
               (lambda (surface _b _l) (push surface drilled) t)))
          (with-jetpacs-owner "mail"
            (jetpacs-defaction "mail.show"
                               (lambda (_a _p)
                                 (jetpacs-navigate-buffer "*scratch*")
                                 'accepted)))
          (setq status (jetpacs--dispatch
                        nil '(:action "mail.show")
                        (gethash "mail.show" jetpacs-action-handlers))))
      (jetpacs-undefaction "mail.show")
      (jetpacs-test-reset-state))
    (should (eq status 'accepted))
    (should (equal drilled '("app:mail")))))

(provide 'jetpacs-navigate-test)
;;; jetpacs-navigate-test.el ends here
