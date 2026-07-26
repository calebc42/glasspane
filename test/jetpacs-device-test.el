;;; jetpacs-device-test.el --- JA-1 reminders wrapper exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JA-1 reminders half of the exit gate (docs/PLAN-jetpacs-apps.md).
;; Every wire interaction is captured at `ebp-client--request' with the
;; callback held, so the suite drives acceptance, rejection, W10
;; refusal, and crossed responses deterministically.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-device)

(defvar jetpacs-device-test--calls nil
  "Captured (METHOD PARAMS CALLBACK) per wire request, newest first.")

(defun jetpacs-device-test--client (&optional granted)
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jetpacs-device-receipts"))))
    (setf (ebp-client-state client) 'ready
          (ebp-client-granted client) (or granted ["reminders.owner"]))
    client))

(defmacro jetpacs-device-test--with (client-form &rest body)
  "Attach CLIENT-FORM, capture wire calls, run BODY, always clean up."
  (declare (indent 1))
  `(let ((client ,client-form)
         (jetpacs-device-test--calls nil))
     (cl-letf (((symbol-function 'ebp-client--request)
                (lambda (_client method params callback &optional _timeout)
                  (push (list method params callback)
                        jetpacs-device-test--calls)
                  42)))
       (unwind-protect
           (progn (jetpacs-attach client) ,@body)
         (jetpacs-detach)
         (jetpacs-test-reset-state)))))

(defun jetpacs-device-test--resolve (n count &optional err)
  "Conclude the Nth-newest captured call with (COUNT ERR)."
  (funcall (nth 2 (nth n jetpacs-device-test--calls))
           (and (not err) (list :count count)) err))

;;;; Owner and gates

(ert-deftest jetpacs-device-owner-defaults-from-context ()
  (jetpacs-device-test--with (jetpacs-device-test--client)
    (with-jetpacs-owner "org.agenda"
      (jetpacs-reminders-set
       (list '(:id "r1" :title "T" :at_ms 1784700000000))))
    (should (= (length jetpacs-device-test--calls) 1))
    (pcase-let ((`(,method ,params ,_cb) (car jetpacs-device-test--calls)))
      (should (eq method 'reminders.set))
      (should (equal (plist-get params :owner) "org.agenda"))
      (should (equal (plist-get params :reminders)
                     [(:id "r1" :title "T" :at_ms 1784700000000)])))))

(ert-deftest jetpacs-device-owner-required ()
  (jetpacs-device-test--with (jetpacs-device-test--client)
    (should-error (jetpacs-reminders-set
                   '((:id "r" :title "T" :at_ms 1))))
    (should-error (jetpacs-reminders-set
                   '((:id "r" :title "T" :at_ms 1)) :owner "bad:colon"))
    (should-error (jetpacs-reminders-set
                   '((:id "r" :title "T" :at_ms 1)) :owner ""))
    (should (= (length jetpacs-device-test--calls) 0))))

(ert-deftest jetpacs-device-granted-gate ()
  (jetpacs-device-test--with (jetpacs-device-test--client [])
    (let ((err (should-error (jetpacs-reminders-set
                              '((:id "r" :title "T" :at_ms 1))
                              :owner "a"))))
      (should (string-match-p "reminders\\.owner" (cadr err))))
    (should (= (length jetpacs-device-test--calls) 0)))
  ;; No client attached at all.
  (should-error (jetpacs-reminders-set '((:id "r" :title "T" :at_ms 1))
                                       :owner "a")))

;;;; Validation

(ert-deftest jetpacs-device-validation-rejects ()
  (jetpacs-device-test--with (jetpacs-device-test--client)
    (dolist (bad '(((:id "a" :title "T" :at_ms 1)
                    (:id "a" :title "T" :at_ms 2))   ; duplicate ids
                   ((:id "has space" :title "T" :at_ms 1))
                   ((:id "r" :title "" :at_ms 1))
                   ((:id "r" :at_ms 1))              ; missing title
                   ((:id "r" :title "T" :at_ms 1.7847e12)) ; float (RA-5)
                   ((:id "r" :title "T" :at_ms "123"))
                   ((:id "r" :title "T" :at_ms 1 :priority 1)) ; unknown member
                   (((id . "x") (title . "T") (at_ms . 1)))    ; alist input
                   ((:id "r" :title "T" :at_ms 1
                     :on_tap (:builtin "view.switch" :view "v")))
                   ((:id "r" :title "T" :at_ms 1
                     :on_tap (:action "a.b" :args (:owner "x"))))
                   ((:id "r" :title "T" :at_ms 1
                     :on_tap (:action "a.b" :args (:reminder_id "x"))))
                   ((:id "r" :title "T" :at_ms 1
                     :on_tap (:action "a.b" :capture_fields ["f"])))))
      (should-error (jetpacs-reminders-set bad :owner "a"))
      (should (= (length jetpacs-device-test--calls) 0)))))

(ert-deftest jetpacs-device-nil-members-stripped ()
  (jetpacs-device-test--with (jetpacs-device-test--client)
    (jetpacs-reminders-set '((:id "r" :title "T" :body nil :at_ms 5
                              :on_tap nil))
                           :owner "a")
    (let ((elem (aref (plist-get (nth 1 (car jetpacs-device-test--calls))
                                 :reminders)
                      0)))
      (should-not (plist-member elem :body))
      (should-not (plist-member elem :on_tap)))))

(ert-deftest jetpacs-device-on-tap-built-with-jetpacs-action ()
  (jetpacs-device-test--with (jetpacs-device-test--client)
    ;; Register the action so the advisory warning stays silent.
    (with-jetpacs-owner "agenda"
      (jetpacs-defaction "agenda.open" (lambda (_a _p) 'accepted)))
    (jetpacs-reminders-set
     (list (list :id "r" :title "T" :at_ms 5
                 :on_tap (jetpacs-action "agenda.open"
                                         :args '(:day "2026-07-26")
                                         :when-offline 'queue :ttl-s 3600)))
     :owner "agenda")
    (let ((elem (aref (plist-get (nth 1 (car jetpacs-device-test--calls))
                                 :reminders)
                      0)))
      (should (equal (plist-get elem :on_tap)
                     '(:action "agenda.open" :args (:day "2026-07-26")
                       :when_offline "queue" :ttl_s 3600))))))

;;;; Replace-set semantics and the mirror

(ert-deftest jetpacs-device-replace-set-per-owner-isolation ()
  (jetpacs-device-test--with (jetpacs-device-test--client)
    (jetpacs-reminders-set '((:id "a1" :title "T" :at_ms 1)
                             (:id "a2" :title "T" :at_ms 2))
                           :owner "a")
    (jetpacs-device-test--resolve 0 2)
    (jetpacs-reminders-set '((:id "b1" :title "T" :at_ms 3)) :owner "b")
    (jetpacs-device-test--resolve 0 1)
    (jetpacs-reminders-set '((:id "a3" :title "T" :at_ms 4)) :owner "a")
    (jetpacs-device-test--resolve 0 1)
    (should (= (length jetpacs-device-test--calls) 3))
    ;; Each wire call carried only its owner's vector.
    (should (equal (plist-get (nth 1 (nth 0 jetpacs-device-test--calls)) :owner) "a"))
    (should (equal (plist-get (nth 1 (nth 1 jetpacs-device-test--calls)) :owner) "b"))
    (should (= (plist-get (jetpacs-reminders "a") :count) 1))
    (should (equal (aref (plist-get (jetpacs-reminders "a") :reminders) 0)
                   '(:id "a3" :title "T" :at_ms 4)))
    (should (= (plist-get (jetpacs-reminders "b") :count) 1))))

(ert-deftest jetpacs-device-clear-sends-empty-and-removes-entry ()
  (jetpacs-device-test--with (jetpacs-device-test--client)
    (jetpacs-reminders-set '((:id "r" :title "T" :at_ms 1)) :owner "a")
    (jetpacs-device-test--resolve 0 1)
    (should (jetpacs-reminders "a"))
    (jetpacs-reminders-clear "a")
    (should (equal (plist-get (nth 1 (car jetpacs-device-test--calls))
                              :reminders)
                   []))
    (jetpacs-device-test--resolve 0 0)
    (should-not (jetpacs-reminders "a"))))

(ert-deftest jetpacs-device-rejection-keeps-bookkeeping ()
  (jetpacs-device-test--with (jetpacs-device-test--client)
    (let ((cb-seen nil) (logged nil))
      (jetpacs-reminders-set '((:id "r1" :title "T" :at_ms 1)
                               (:id "r2" :title "T" :at_ms 2))
                             :owner "a")
      (jetpacs-device-test--resolve 0 2)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (push (apply #'format fmt args) logged))))
        (jetpacs-reminders-set '((:id "r3" :title "T" :at_ms 3))
                               :owner "a"
                               :callback (lambda (c e) (setq cb-seen (cons c e))))
        (jetpacs-device-test--resolve
         0 nil '(:code 1201 :message "SECRET-TITLE"
                 :data (:kind "content-invalid" :reason "reminder-limit"))))
      ;; Mirror still the FIRST accepted set; caller saw the error; the
      ;; log carried code + reason but never the wire :message.
      (should (= (plist-get (jetpacs-reminders "a") :count) 2))
      (should (null (car cb-seen)))
      (should (= (plist-get (cdr cb-seen) :code) 1201))
      (should (cl-some (lambda (s) (and (string-match-p "1201" s)
                                        (string-match-p "reminder-limit" s)))
                      logged))
      (should-not (cl-some (lambda (s) (string-match-p "SECRET-TITLE" s))
                           logged)))))

(ert-deftest jetpacs-device-stale-response-cannot-overwrite ()
  (jetpacs-device-test--with (jetpacs-device-test--client)
    (jetpacs-reminders-set '((:id "r1" :title "T" :at_ms 1)
                             (:id "r2" :title "T" :at_ms 2))
                           :owner "a")           ; set#1 (older)
    (jetpacs-reminders-set '((:id "r3" :title "T" :at_ms 3))
                           :owner "a")           ; set#2 (newer)
    ;; Resolve NEWER first, then the stale one.
    (jetpacs-device-test--resolve 0 1)
    (jetpacs-device-test--resolve 1 2)
    (should (= (plist-get (jetpacs-reminders "a") :count) 1))
    (should (equal (aref (plist-get (jetpacs-reminders "a") :reminders) 0)
                   '(:id "r3" :title "T" :at_ms 3)))))

(ert-deftest jetpacs-device-w10-nil-id ()
  (jetpacs-device-test--with (jetpacs-device-test--client)
    (let ((refusals 0))
      (cl-letf (((symbol-function 'ebp-client--request)
                 (lambda (_c _m _p callback &optional _t)
                   (funcall callback nil
                            '(:code 1401
                              :message "Outstanding requests exhausted"
                              :data (:kind "overloaded")))
                   nil)))
        (should-not
         (jetpacs-reminders-set
          '((:id "r" :title "T" :at_ms 1)) :owner "a"
          :callback (lambda (_c err)
                      (when (eql (plist-get err :code) 1401)
                        (cl-incf refusals))))))
      (should (= refusals 1))
      (should-not (jetpacs-reminders "a")))))

(ert-deftest jetpacs-device-reset-hook-is-wired ()
  (jetpacs-device-test--with (jetpacs-device-test--client)
    (jetpacs-reminders-set '((:id "r" :title "T" :at_ms 1)) :owner "a")
    (jetpacs-device-test--resolve 0 1)
    (should (jetpacs-reminders "a")))
  ;; The --with macro's teardown ran jetpacs-test-reset-state, which must
  ;; have swept the device tables through the fboundp hook.
  (should-not (jetpacs-reminders "a")))

(provide 'jetpacs-device-test)
;;; jetpacs-device-test.el ends here
